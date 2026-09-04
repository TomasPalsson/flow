import React, { useState, useEffect } from 'react';

interface WidgetProps {
  title: string;
  items: string[];
  onSelect: (item: string) => void;
}

export function Widget({ title, items, onSelect }: WidgetProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');

  useEffect(() => {
    if (!open) {
      setQuery('');
    }
  }, [open]);

  const filtered = items.filter((item) =>
    item.toLowerCase().includes(query.toLowerCase())
  );

  const handleToggle = () => {
    setOpen((prev) => !prev);
  };

  return (
    <div className="widget">
      <header className="widget-header" onClick={handleToggle}>
        <h2>{title}</h2>
        <span className="widget-count">{items.length}</span>
      </header>
      {open && (
        <div className="widget-body">
          <input
            className="widget-search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search…"
          />
          <ul className="widget-list">
            {filtered.map((item) => (
              <li
                key={item}
                className="widget-list-item"
                onClick={() => onSelect(item)}
              >
                {item}
              </li>
            ))}
          </ul>
          {filtered.length === 0 && (
            <p className="widget-empty">No matches</p>
          )}
        </div>
      )}
    </div>
  );
}

export default Widget;

export const WIDGET_DEFAULT_PROPS: Partial<WidgetProps> = {
  title: 'Untitled',
  items: [],
};

export type WidgetVariant = 'default' | 'compact' | 'expanded';

export interface WidgetTheme {
  background: string;
  foreground: string;
  accent: string;
}

export const LIGHT_THEME: WidgetTheme = {
  background: '#ffffff',
  foreground: '#111111',
  accent: '#3366ff',
};

export const DARK_THEME: WidgetTheme = {
  background: '#111111',
  foreground: '#eeeeee',
  accent: '#88aaff',
};

// Widget CSS class names, kept here so consumers can target them
// without reaching into the component internals.
export const WIDGET_CLASSNAMES = {
  root: 'widget',
  header: 'widget-header',
  count: 'widget-count',
  body: 'widget-body',
  search: 'widget-search',
  list: 'widget-list',
  listItem: 'widget-list-item',
  empty: 'widget-empty',
};
// note: 99
// note: 100
// note: 101
// note: 102
// note: 103
// note: 104
// note: 105
// note: 106
// note: 107
