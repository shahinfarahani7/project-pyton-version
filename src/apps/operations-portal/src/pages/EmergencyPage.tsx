import { useState } from 'react';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';

export function EmergencyPage() {
  const { operatorId, hasPermission } = useSession();
  const [status, setStatus] = useState('');

  if (!hasPermission('operations.break_glass')) {
    return <section className="panel"><p>Break-glass permission required.</p></section>;
  }

  return (
    <section className="panel">
      <h1>Emergency controls</h1>
      <p>Break-glass access is time-bound, paged, recorded, and retrospectively reviewed.</p>
      <button
        type="button"
        onClick={() => {
          void opsApi
            .activateBreakGlass({
              operatorId,
              role: 'operator.break_glass',
              reasonCode: 'incident_response',
              ticketId: 'INC-BG-1',
            })
            .then((body) => setStatus(`Active until ${String(body.expiresAt)}`))
            .catch((err: Error) => setStatus(err.message));
        }}
      >
        Activate break-glass
      </button>
      {status ? <p role="status">{status}</p> : null}
    </section>
  );
}
