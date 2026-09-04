# Bedrock Identity — Deep Dive

This is the comprehensive guide to authentication and authorization in Bedrock AgentCore. It covers both the simple decorator approach and the advanced programmatic workload identity pattern.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setting Up Identity Providers](#setting-up-identity-providers)
3. [Approach 1: @requires_access_token Decorator](#approach-1-requires_access_token-decorator)
4. [Approach 2: Programmatic Workload Identity](#approach-2-programmatic-workload-identity)
5. [The Workload Class Pattern](#the-workload-class-pattern)
6. [MCP Server Integration](#mcp-server-integration)
7. [Auth Flows: M2M vs USER_FEDERATION](#auth-flows-m2m-vs-user_federation)
8. [Token Management](#token-management)
9. [Identity Provider Configuration](#identity-provider-configuration)
10. [Production Patterns](#production-patterns)

---

## Architecture Overview

Bedrock Identity provides OAuth2-based authentication for AgentCore agents. The flow:

```
User → Agent → Bedrock Identity → Identity Provider (Google/GitHub/Cognito/etc.)
                                          ↓
                                   Authorization URL
                                          ↓
                                   User grants access
                                          ↓
                                   Callback → Token
                                          ↓
                                   Agent uses token
```

Key components:
- **IdentityClient**: SDK client for managing workload identities and tokens
- **Workload Identity**: A unique identity for your agent, used to obtain tokens
- **OAuth Provider**: External identity provider (Google, GitHub, Cognito, Okta, custom OIDC)
- **Callback URL**: Where the OAuth provider redirects after user authorization

---

## Setting Up Identity Providers

### Quick Setup with Cognito

```bash
# Install the CLI
pip install bedrock-agentcore-starter-toolkit

# Setup Cognito (creates user pool, client, outputs IDs)
agentcore identity setup-cognito

# Load the generated environment variables
export $(grep -v '^#' .agentcore_identity_user.env | xargs)
```

This creates:
- A Cognito User Pool
- An app client
- A discovery URL
- Environment variables: `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `COGNITO_DISCOVERY_URL`

### Register OAuth Providers via Console or CLI

OAuth providers (Google, GitHub, etc.) must be registered in the Bedrock Identity console before use. You'll need:
- Provider name (referenced in code)
- Client ID + Client Secret from the provider
- Scopes your agent needs
- Redirect/callback URI

---

## Approach 1: @requires_access_token Decorator

The simple approach. The decorator handles the entire OAuth flow automatically.

```python
from bedrock_agentcore.identity.auth import requires_access_token
from strands import tool

@tool
@requires_access_token(
    provider_name="google-oauth",
    scopes=[
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/documents",
    ],
)
def list_google_files(access_token: str) -> dict:
    """List files in Google Drive. Auth is handled automatically."""
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build

    creds = Credentials(token=access_token)
    service = build("drive", "v3", credentials=creds)
    results = service.files().list(pageSize=10).execute()
    return {"status": "success", "files": results.get("files", [])}
```

**How it works**: The decorator intercepts the tool call, checks if a valid token exists, initiates the OAuth flow if needed, and injects the `access_token` parameter once authenticated.

**When to use**: Simple agents where you don't need to control the auth UX. The decorator blocks until auth completes — the agent cannot show the user an authorization URL.

**When NOT to use**: Interactive MCP servers or agents where you need to return the auth URL to the user for them to click.

---

## Approach 2: Programmatic Workload Identity

When you need full control over the OAuth flow — especially when the agent must surface an authorization URL to the user.

### Core Concepts

1. **Workload Identity**: An identity you create for your agent. Each user can have their own workload identity (or share one). The identity is used to obtain workload access tokens.

2. **Workload Access Token**: A token that represents the agent's identity. Used to request OAuth tokens from providers on behalf of users.

3. **`on_auth_url` callback**: A function called by `IdentityClient.get_token()` with the authorization URL before the OAuth flow redirects. This is how you capture the URL to show the user.

4. **`asyncio.Future` bridge**: The `on_auth_url` callback fires synchronously inside the `get_token` flow. Use a Future to bridge it to async code and return the URL immediately.

### The IdentityClient API

```python
from bedrock_agentcore.services.identity import IdentityClient
from bedrock_agentcore.identity.auth import _get_region

client = IdentityClient(_get_region())

# Create a workload identity
resp = client.create_workload_identity()
identity_name = resp["name"]

# Configure allowed callback URLs
client.update_workload_identity(
    name=identity_name,
    allowed_resource_oauth_2_return_urls=["https://your-domain.com/redirect"],
)

# Get a workload access token
resp = client.get_workload_access_token(identity_name, user_id="user-123")
agent_token = resp["workloadAccessToken"]

# Get an OAuth token (this triggers the OAuth flow)
oauth_token = await client.get_token(
    provider_name="google-oauth-client",
    agent_identity_token=agent_token,
    scopes=["https://www.googleapis.com/auth/drive"],
    on_auth_url=lambda url: print(f"Auth URL: {url}"),  # Capture this!
    auth_flow="USER_FEDERATION",
    callback_url="https://your-domain.com/redirect",
    force_authentication=True,
    custom_state=json.dumps({"user_id": "user-123"}),
)
```

---

## The Workload Class Pattern

This is the production-ready pattern for programmatic identity management. It encapsulates identity creation, caching, token management, and auth URL capture.

```python
import asyncio
import json
from pathlib import Path
from typing import List, Optional, Literal
import jwt
from fastmcp.server.dependencies import get_http_request
from bedrock_agentcore.services.identity import IdentityClient
from bedrock_agentcore.identity.auth import _get_region


class Workload:
    """Manages Bedrock Identity workload identities and OAuth flows.

    This class provides programmatic control over the OAuth flow,
    allowing agents to capture and return authorization URLs to users
    instead of handling auth silently behind the scenes.
    """

    def __init__(self, callback_url="https://your-domain.com/redirect"):
        self.client = IdentityClient(_get_region())
        self.callback_url = callback_url

    def get_user(self) -> str | dict:
        """Extract user identity from the Authorization header JWT.

        When running as an MCP server in AgentCore, the runtime injects
        a JWT in the Authorization header identifying the calling user.
        """
        req = get_http_request()
        if not req:
            return "No request found"

        auth_header = req.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return {"error": "No valid Authorization header"}

        token = auth_header.split(" ", 1)[1]
        try:
            claims = jwt.decode(token, options={"verify_signature": False})
        except Exception:
            return {"error": "Invalid token"}

        return claims.get("sub")

    def get_workload_identity(self, user_id: str) -> str:
        """Get or create a workload identity for the given user.

        Caches identity names to disk to avoid recreating on every request.
        In production, use DynamoDB or another persistent store.
        """
        path = Path(f".agentcore-{user_id}.json")

        if path.exists():
            try:
                with open(path) as f:
                    return json.load(f)["workload_identity_name"]
            except Exception:
                pass

        resp = self.client.create_workload_identity()
        identity_name = resp["name"]

        # Configure allowed OAuth callback URLs
        self.client.update_workload_identity(
            name=identity_name,
            allowed_resource_oauth_2_return_urls=[self.callback_url],
        )

        with open(path, "w") as f:
            json.dump({"workload_identity_name": identity_name}, f, indent=2)

        return identity_name

    async def get_workload_access_token(self, user_id: str) -> str:
        """Get an agent access token for the given user's workload identity."""
        resp = self.client.get_workload_access_token(
            self.get_workload_identity(user_id), user_id=user_id
        )
        return resp["workloadAccessToken"]

    async def get_oauth_url(
        self,
        provider_name: str,
        scopes: List[str],
        auth_flow: Literal["M2M", "USER_FEDERATION"],
        callback_url: Optional[str] = None,
        force_authentication: bool = True,
    ) -> str:
        """Get an OAuth authorization URL that can be returned to the user.

        This is the key method that differentiates from @requires_access_token.
        It captures the auth URL via the on_auth_url callback and returns it
        immediately, allowing the agent to surface it to the user.

        The trick: get_token() calls on_auth_url with the URL synchronously
        before the flow completes. We use an asyncio.Future to capture it
        and return it right away, while the flow continues in the background.
        """
        user_id = self.get_user()
        if isinstance(user_id, dict) or not user_id:
            raise Exception(f"Invalid user identity: {user_id}")

        loop = asyncio.get_running_loop()
        url_future: asyncio.Future[str] = loop.create_future()

        def on_auth_url(url: str):
            if not url_future.done():
                url_future.set_result(url)

        async def _run_flow():
            try:
                agent_token = await self.get_workload_access_token(user_id)
                await self.client.get_token(
                    provider_name=provider_name,
                    agent_identity_token=agent_token,
                    scopes=scopes,
                    on_auth_url=on_auth_url,
                    auth_flow=auth_flow,
                    callback_url=callback_url or self.callback_url,
                    force_authentication=force_authentication,
                    custom_state=json.dumps({"user_id": user_id}),
                )
            except Exception as e:
                if not url_future.done():
                    url_future.set_exception(e)

        asyncio.create_task(_run_flow())
        return await url_future

    async def get_google_auth_url(self) -> dict:
        """Get Google OAuth URL with Drive scopes. Returns structured response."""
        try:
            url = await self.get_oauth_url(
                provider_name="google-oauth-client",  # Your registered provider name
                scopes=[
                    "https://www.googleapis.com/auth/drive",
                    "https://www.googleapis.com/auth/documents",
                ],
                auth_flow="USER_FEDERATION",
                force_authentication=True,
            )
            return {
                "type": "authorization_required",
                "authorization_url": url,
                "message": "Open this link and grant access to Google Drive.",
            }
        except Exception as e:
            return {"type": "error", "message": str(e)}

    async def get_token(self) -> str | dict:
        """Try to get an existing OAuth token. If expired, return auth URL.

        This is the "try token, fallback to auth URL" pattern.
        Tools call this first — if auth is needed, the structured
        response tells the agent to surface the URL to the user.
        """
        user_id = self.get_user()
        if isinstance(user_id, dict) or not user_id:
            raise Exception("Invalid user identity")

        try:
            agent_token = await self.get_workload_access_token(user_id)
            return await self.client.get_token(
                provider_name="google-oauth-client",
                scopes=[
                    "https://www.googleapis.com/auth/drive",
                    "https://www.googleapis.com/auth/documents",
                ],
                agent_identity_token=agent_token,
                auth_flow="USER_FEDERATION",
                force_authentication=False,  # Don't force re-auth if token exists
            )
        except Exception:
            # Token missing or expired — return auth URL
            auth_url = await self.get_oauth_url(
                provider_name="google-oauth-client",
                auth_flow="USER_FEDERATION",
                scopes=[
                    "https://www.googleapis.com/auth/drive",
                    "https://www.googleapis.com/auth/documents",
                ],
                force_authentication=True,
            )
            return {
                "type": "authorization_required",
                "message": "Google authorization required",
                "authorization_url": auth_url,
            }
```

---

## MCP Server Integration

Here's how to build an MCP server that uses the Workload pattern to authenticate users:

```python
from mcp.server.fastmcp import FastMCP
from workload import Workload

instructions = """
You help users manage their Google Drive files.
To access files, you must first authenticate the user:
1. Use the 'get_google_auth_url' tool to get the auth URL
2. Write out the URL directly to the user — they must click it
3. After auth, you can use the other tools to access their files
"""

mcp = FastMCP(
    host="0.0.0.0",
    port=8000,
    stateless_http=True,
    instructions=instructions,
)

workload = Workload(callback_url="https://your-domain.com/redirect")


@mcp.tool()
async def get_google_auth_url() -> dict:
    """Get Google OAuth authorization URL.
    You need to write out this URL for the user to copy and paste.
    """
    return await workload.get_google_auth_url()


@mcp.tool()
async def list_drive_files(query: str = "") -> dict:
    """List files from Google Drive. Requires authentication first."""
    token = await workload.get_token()

    # If token is a dict, auth is required
    if isinstance(token, dict):
        return token

    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build

    creds = Credentials(token=token)
    service = build("drive", "v3", credentials=creds)
    results = service.files().list(pageSize=10, q=query).execute()
    return {"type": "success", "files": results.get("files", [])}


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
```

### The Toolset Pattern

For organizing many tools, use a base class:

```python
import inspect
from mcp.server.fastmcp import FastMCP


def tool(func):
    """Decorator to mark a method as a tool."""
    func.__is_tool = True
    return func


class Toolset:
    """Base class for tool groups. Register all @tool methods with an MCP server."""

    def import_tools(self, mcp: FastMCP):
        for name, method in inspect.getmembers(self, predicate=inspect.ismethod):
            if getattr(method, "__is_tool", False):
                mcp.add_tool(fn=method, name=name, description=method.__doc__)


class DriveToolset(Toolset):
    def __init__(self):
        self.workload = Workload()

    @tool
    async def get_google_auth_url(self) -> dict:
        """Get Google OAuth authorization URL."""
        return await self.workload.get_google_auth_url()

    @tool
    async def fetch_files(self, query: str = "") -> dict:
        """Fetch Google Drive files."""
        token = await self.workload.get_token()
        if isinstance(token, dict):
            return token
        # ... use token to access Google APIs


# Register tools
toolset = DriveToolset()
toolset.import_tools(mcp)
```

---

## Auth Flows: M2M vs USER_FEDERATION

### USER_FEDERATION

The user authenticates directly. The agent gets a token scoped to that user's permissions.

```python
await client.get_token(
    auth_flow="USER_FEDERATION",
    # User sees a consent screen, grants access
    # Token represents the user's permissions
)
```

**Use when**: The agent acts on behalf of a specific user (accessing their Drive, their GitHub, etc.)

### M2M (Machine-to-Machine)

The agent authenticates as itself using client credentials. No user interaction needed.

```python
await client.get_token(
    auth_flow="M2M",
    # No user consent — agent authenticates with its own credentials
    # Token represents the agent's permissions
)
```

**Use when**: The agent accesses shared resources, APIs, or services that don't need per-user auth.

---

## Token Management

### Caching Strategy

The Workload class caches workload identity names to disk. In production, use a proper store:

```python
# Development: File-based caching
path = Path(f".agentcore-{user_id}.json")

# Production: DynamoDB
import boto3
table = boto3.resource("dynamodb").Table("agent-identities")
table.put_item(Item={"user_id": user_id, "identity_name": identity_name})
```

### Token Refresh

- `force_authentication=False`: Reuses existing tokens if valid
- `force_authentication=True`: Always generates a new auth URL (for initial auth or re-auth)

The `get_token()` method in IdentityClient handles refresh internally when `force_authentication=False`.

### Custom State

Pass custom data through the OAuth flow using `custom_state`:

```python
await self.client.get_token(
    custom_state=json.dumps({"user_id": user_id, "session_id": "abc123"}),
    # ... other params
)
```

This state is passed through the OAuth redirect and available in the callback.

---

## Identity Provider Configuration

### Google OAuth

1. Create credentials in Google Cloud Console
2. Register as OAuth provider in Bedrock Identity:
   - Provider name: `google-oauth-client` (or your chosen name)
   - Client ID from Google
   - Client Secret from Google
   - Scopes: `https://www.googleapis.com/auth/drive`, etc.
3. Add your callback URL to Google's authorized redirect URIs

### GitHub OAuth

1. Create an OAuth App in GitHub Settings
2. Register in Bedrock Identity:
   - Provider name: `github-oauth-client`
   - Client ID + Secret from GitHub
   - Scopes: `repo`, `read:user`, etc.

### Cognito

```bash
agentcore identity setup-cognito
```

This creates everything automatically.

### Custom OIDC

Any OIDC-compliant provider can be registered:
- Discovery URL (`.well-known/openid-configuration`)
- Client ID + Secret
- Scopes

---

## Production Patterns

### Multi-Provider Auth

An agent that needs both Google and GitHub:

```python
class MultiProviderWorkload(Workload):
    async def get_google_auth_url(self) -> dict:
        return await self._get_auth_url("google-oauth-client", [
            "https://www.googleapis.com/auth/drive",
        ])

    async def get_github_auth_url(self) -> dict:
        return await self._get_auth_url("github-oauth-client", [
            "repo", "read:user",
        ])

    async def _get_auth_url(self, provider: str, scopes: list) -> dict:
        try:
            url = await self.get_oauth_url(
                provider_name=provider,
                scopes=scopes,
                auth_flow="USER_FEDERATION",
            )
            return {
                "type": "authorization_required",
                "authorization_url": url,
                "provider": provider,
            }
        except Exception as e:
            return {"type": "error", "message": str(e)}
```

### Error Handling Pattern

```python
async def safe_get_token(self, provider: str, scopes: list) -> str | dict:
    """Get token with graceful fallback to auth URL."""
    try:
        user_id = self.get_user()
        if isinstance(user_id, dict):
            return {"type": "error", "message": "User not authenticated to AgentCore"}

        agent_token = await self.get_workload_access_token(user_id)
        return await self.client.get_token(
            provider_name=provider,
            scopes=scopes,
            agent_identity_token=agent_token,
            auth_flow="USER_FEDERATION",
            force_authentication=False,
        )
    except Exception:
        try:
            url = await self.get_oauth_url(
                provider_name=provider,
                scopes=scopes,
                auth_flow="USER_FEDERATION",
                force_authentication=True,
            )
            return {"type": "authorization_required", "authorization_url": url}
        except Exception as e:
            return {"type": "error", "message": f"Auth failed: {str(e)}"}
```

### Extracting User Identity from JWT

When running in AgentCore, the runtime provides a JWT identifying the caller:

```python
import jwt

def get_user_from_request() -> str | None:
    """Extract user sub from the AgentCore-provided JWT."""
    from fastmcp.server.dependencies import get_http_request

    req = get_http_request()
    if not req:
        return None

    auth = req.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None

    token = auth.split(" ", 1)[1]
    claims = jwt.decode(token, options={"verify_signature": False})
    return claims.get("sub")
```

Note: In production, verify the JWT signature. Skipping verification (`verify_signature=False`) is only for development/prototyping.

### Client-Side Token Generation

For CLI agents or frontends that need to authenticate to AgentCore:

```bash
# Generate a bearer token for calling AgentCore
agentcore identity get-token
```

Or programmatically with Cognito:

```python
import requests
import urllib.parse

# Build auth URL
params = {
    "response_type": "code",
    "client_id": COGNITO_CLIENT_ID,
    "redirect_uri": REDIRECT_URI,
    "scope": "email openid profile",
}
auth_url = f"{COGNITO_DOMAIN}/oauth2/authorize?{urllib.parse.urlencode(params)}"

# After user logs in and you get the auth code:
token_resp = requests.post(
    f"{COGNITO_DOMAIN}/oauth2/token",
    data={
        "grant_type": "authorization_code",
        "client_id": COGNITO_CLIENT_ID,
        "client_secret": COGNITO_CLIENT_SECRET,
        "code": auth_code,
        "redirect_uri": REDIRECT_URI,
    },
)
access_token = token_resp.json()["access_token"]
```
