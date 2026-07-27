import { useEffect, useState } from 'react';

import { opsApi } from '../api/client';

export function ResourceView({ view, title }: { view: string; title: string }) {
  const [items, setItems] = useState<Record<string, unknown>[]>([]);

  useEffect(() => {
    opsApi.search(view).then((body) => setItems(body.items)).catch(() => setItems([]));
  }, [view]);

  return (
    <section className="panel">
      <h1>{title}</h1>
      <table>
        <thead>
          <tr>
            <th scope="col">ID</th>
            <th scope="col">Status</th>
          </tr>
        </thead>
        <tbody>
          {items.map((item) => (
            <tr key={String(item.id)}>
              <td>{String(item.id)}</td>
              <td>{String(item.status ?? 'unknown')}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
