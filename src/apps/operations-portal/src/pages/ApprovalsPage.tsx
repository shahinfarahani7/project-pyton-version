import { useState } from 'react';

import { opsApi } from '../api/client';
import { useSession } from '../auth/session';

export function ApprovalsPage() {
  const { operatorId, hasPermission } = useSession();
  const [approvalId, setApprovalId] = useState('');
  const [message, setMessage] = useState('');

  if (!hasPermission('operations.approve')) {
    return <section className="panel"><p>Approval permission required.</p></section>;
  }

  return (
    <section className="panel">
      <h1>Four-eyes approvals</h1>
      <p>High-risk actions require an independent approver. Self-approval is blocked.</p>
      <label>
        Approval ID
        <input value={approvalId} onChange={(e) => setApprovalId(e.target.value)} />
      </label>
      <button
        type="button"
        onClick={() => {
          void opsApi
            .approve(approvalId, { approverId: operatorId, role: 'operator.approver' })
            .then((body) => setMessage(String(body.status ?? 'approved')))
            .catch((err: Error) => setMessage(err.message));
        }}
      >
        Approve action
      </button>
      {message ? <p role="status">{message}</p> : null}
    </section>
  );
}
