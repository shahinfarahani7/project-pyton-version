export const navLinks = [
  { name: 'how-it-works', label: 'How it works' },
  { name: 'use-cases', label: 'Use cases' },
  { name: 'security', label: 'Security' },
  { name: 'workers', label: 'Workers' },
  { name: 'developers', label: 'Developers' },
];

export const hero = {
  eyebrow: 'Edge-first AI inference',
  title: 'Run AI tasks on everyday phones — with your first month free.',
  titleHighlight: 'your first month free',
  subtitle:
    'FibonAI sends document, vision, and language tasks to at least three verified phones, returns only the answer they agree on, and keeps a full audit trail — with explicit cloud fallback when your policy allows.',
  primaryCta: { label: 'Talk to sales', to: 'contact' },
  secondaryCta: { label: 'View documentation', to: 'docs' },
};

export const stats = [
  { value: '60+', label: 'Task types in catalog', icon: '⬡' },
  { value: '1 month', label: 'Free to start, API included', icon: '✦' },
  { value: '3+', label: 'Phones check every task', icon: '◈' },
  { value: 'Audit', label: 'Immutable event trail', icon: '⛨' },
];

export const trustBadges = [
  { icon: '⛨', label: 'Signed models' },
  { icon: '✦', label: 'First month free' },
  { icon: '◎', label: '3-phone consensus' },
  { icon: '◈', label: 'Edge-preferred routing' },
  { icon: '⬡', label: '60+ task types' },
  { icon: '✓', label: 'GDPR-ready architecture' },
  { icon: '⟡', label: 'Async + webhooks' },
  { icon: '⛓', label: 'Immutable audit trail' },
  { icon: '◎', label: 'Verification tiers' },
];

export const pillars = [
  {
    icon: '◈',
    title: 'Edge-preferred execution',
    body: 'Workloads run on opted-in devices when policy and SLA allow. Cloud fallback is never silent — the reason is recorded.',
  },
  {
    icon: '✦',
    title: 'First month free',
    body: 'New accounts get a free first month with free API access. Each task is assessed for difficulty first, so you know how many credits it uses before it runs.',
  },
  {
    icon: '⛨',
    title: 'Consensus, not trust',
    body: 'Every task goes to at least three independent phones. Only the answer they agree on comes back to you; cheating devices are warned, then removed.',
  },
];

export const flowSteps = [
  {
    step: '01',
    title: 'Submit a task',
    body: 'Upload a document, image, or text payload via portal or API. Attach instructions and pick a task type from the catalog.',
  },
  {
    step: '02',
    title: 'Quick assessment',
    body: 'FibonAI checks the task is safe, estimates its difficulty and time, and shows how many credits it uses — never a price.',
  },
  {
    step: '03',
    title: 'Edge execution',
    body: 'The platform sends the task to at least three eligible phones. Each runs signed on-device models and streams lifecycle events to your workspace.',
  },
  {
    step: '04',
    title: 'Consensus & result',
    body: 'Answers are compared and only the agreed result lands in your portal or webhook. Every attempt, revision, and credit event stays in the ledger.',
  },
];

export const useCaseGroups = [
  {
    title: 'Document intelligence',
    items: ['Invoice & receipt OCR', 'Structured field extraction', 'Document verification', 'Quality scoring'],
  },
  {
    title: 'Vision & moderation',
    items: ['Image classification', 'NSFW & safety checks', 'Catalog tagging', 'Duplicate detection'],
  },
  {
    title: 'Language & NLP',
    items: ['Summarization', 'Translation', 'Text moderation', 'Embedding & generation'],
  },
  {
    title: 'ML operations',
    items: ['Label verification', 'Consensus validation', 'Active-learning pre-label', 'Dataset cleanup'],
  },
];

export const consensusSteps = [
  { step: 'Assess', detail: 'difficulty', outcome: 'credits shown' },
  { step: 'Dispatch', detail: '3+ phones', outcome: 'run independently' },
  { step: 'Compare', detail: 'consensus', outcome: '2 of 3 agree' },
  { step: 'Retry', detail: '+2 phones', outcome: 'max 10 rounds' },
  { step: 'Deliver', detail: 'agreed only', outcome: 'result + audit' },
];

export const taskFeed = [
  { task: 'document.ocr', file: 'invoice-2291.pdf', meta: 'assessed · 3 phones agree', status: 'ok' },
  { task: 'text.summarize', file: 'board-minutes.txt', meta: 'difficulty 2 · consensus reached', status: 'ok' },
  { task: 'document.verify', file: 'id-scan.png', meta: 'held · region policy EU-only', status: 'held' },
  { task: 'image.classify', file: 'shelf-photo.jpg', meta: 'free credit · 3 phones agree', status: 'ok' },
  { task: 'text.translate', file: 'terms-de.txt', meta: 'cloud fallback · reason recorded', status: 'ok' },
  { task: 'document.ocr', file: 'receipt-118.jpg', meta: 'round 2 · 3 of 5 agree', status: 'ok' },
];

export const assessmentSample = [
  '{',
  '  "task_type": "document.ocr",',
  '  "difficulty": 1,',
  '  "credits": 1,',
  '  "workers": 3,',
  '  "consensus": "min_2_of_3",',
  '  "fallback": "allowed_with_reason",',
  '  "policy_hash": "sha256:9f2c…e41a"',
  '}',
];

export const taskCards = [
  { glyph: 'OCR', title: 'Document OCR', body: 'Invoices, receipts, and forms to structured text.', input: 'PDF or image', to: 'models' },
  { glyph: 'IMG', title: 'Image classify', body: 'Catalog tagging and safety checks on images.', input: 'Image', to: 'models' },
  { glyph: 'TXT', title: 'Text translate', body: 'Contracts, tickets, and support text across languages.', input: 'Text', to: 'models' },
];

export const capabilityChips = [
  { icon: '✦', label: 'First month free' },
  { icon: '◎', label: '3-phone consensus' },
  { icon: '⌖', label: 'Region policies' },
  { icon: '⚯', label: 'Signed webhooks' },
  { icon: '⛨', label: 'Signed models' },
  { icon: '◎', label: 'Verification tiers' },
  { icon: '⛓', label: 'Hash-chained audit log' },
  { icon: '↻', label: 'Idempotent creates' },
  { icon: '⇄', label: 'Replay & dead-letter' },
];

export const portalNav = ['Tasks', 'Credits', 'Workers', 'Audit log'];

export const portalFields = [
  { label: 'Task type', value: 'document.ocr' },
  { label: 'Input', value: 'invoice-2291.pdf' },
  { label: 'Verification', value: 'standard' },
  { label: 'Region policy', value: 'EU only' },
];

export const integrations = ['REST', 'SSE', 'TS', 'Hooks', 'API', 'Docs'];

export const fanTargets = [
  { label: 'Edge', tone: 'edge' },
  { label: 'Cloud', tone: 'cloud' },
  { label: 'Hook', tone: 'hook' },
  { label: 'Ledger', tone: 'ledger' },
];

export const securityFeatures = [
  {
    title: 'Tenant isolation',
    body: 'Workspace-scoped row-level security on every customer table. Data region policies enforced at intake.',
  },
  {
    title: 'Signed models & attestation',
    body: 'Workers verify model SHA-256 and signature before execution. Device attestation via platform integrity APIs.',
  },
  {
    title: 'Durable eventing',
    body: 'PostgreSQL transactional outbox with secure WebSocket delivery, acknowledgement, replay, and dead-letter handling.',
  },
  {
    title: 'Privacy by design',
    body: 'Worker payloads are ephemeral. Customer identity is never shown to workers. Temp inputs deleted within 15 minutes.',
  },
  {
    title: 'No silent fallback',
    body: 'Cloud execution only when your policy permits. The fallback reason is recorded on every task.',
  },
  {
    title: 'Compliance-ready',
    body: 'GDPR DPIA checklist, DPA/subprocessor registry, hash-chained audit logs, and store-review evidence packs.',
  },
];

export const workerPoints = [
  'Explicit availability toggle — tasks run only while you opt in.',
  'Battery, Wi-Fi, and thermal controls stay under your settings.',
  'Earn FibonAI tokens when your answer matches the consensus. No guaranteed income.',
  'Not crypto mining — on-device AI inference for assigned tasks only.',
  'Foreground processing indicator while a task is active.',
  'Model downloads are signed and verified before execution.',
];

export const developerPoints = [
  'Async task lifecycle with webhooks and idempotent create APIs.',
  '141-operation public OpenAPI contract with generated TypeScript client.',
  'Portal dev sign-in for local integration against the task catalog.',
  'Task types span OCR, vision, moderation, NLP, and ML validation.',
  'Verification tiers from standard through consensus to human review.',
  'Developer plan with published SLA targets — contact us for production keys.',
];

export const contactChannels = [
  { label: 'Sales & enterprise', value: 'sales@edgemint.io' },
  { label: 'Developer support', value: 'developers@edgemint.io' },
  { label: 'Security & privacy', value: 'security@edgemint.io' },
];

export const legalLinks = [
  { label: 'Privacy Policy', slug: 'privacy' },
  { label: 'Terms of Service', slug: 'terms' },
  { label: 'Worker Participation Terms', slug: 'workers' },
  { label: 'Data Processing Addendum', slug: 'dpa' },
];

export const modelCategories = [
  {
    title: 'Document intelligence',
    count: 14,
    input: 'PDF, image, or text uploads',
    samples: ['Invoice & receipt OCR', 'Structured field extraction', 'Document verification', 'Quality scoring'],
  },
  {
    title: 'Vision & catalog',
    count: 18,
    input: 'Image uploads',
    samples: ['Image classification', 'Product tagging', 'Duplicate detection', 'Background removal'],
  },
  {
    title: 'Safety & moderation',
    count: 12,
    input: 'Image or text payloads',
    samples: ['NSFW detection', 'Violence & weapon checks', 'Text moderation', 'Prompt safety'],
  },
  {
    title: 'Language & NLP',
    count: 16,
    input: 'Text or audio',
    samples: ['Summarization', 'Translation', 'Embeddings', 'Audio transcription'],
  },
];

export const docsSections = [
  {
    title: 'REST API reference',
    body: '141-operation OpenAPI contract covering task create, assessment, lifecycle, webhooks, and workspace administration.',
    links: [{ label: 'Developer integration guide', to: 'developers' }],
  },
  {
    title: 'Task catalog',
    body: 'Browse supported task types, input modes, and verification options before you integrate.',
    links: [
      { label: 'Models & task types', to: 'models' },
      { label: 'Use cases', to: 'use-cases' },
    ],
  },
  {
    title: 'Authentication & webhooks',
    body: 'Workspace-scoped API keys, idempotent creates, and signed webhook delivery with replay protection.',
    links: [{ label: 'Security architecture', to: 'security' }],
  },
  {
    title: 'Credits & assessment',
    body: 'Your first month is free. Each task is assessed for difficulty before it runs, so you know how many credits it uses.',
    links: [{ label: 'How it works', to: 'how-it-works' }],
  },
];

export const statusComponents = [
  { name: 'API Gateway', role: 'Public REST & portal API', status: 'Operational' },
  { name: 'Worker Registry', role: 'Assignment routing & lifecycle', status: 'Operational' },
  { name: 'Event delivery', role: 'SSE & webhook outbox', status: 'Operational' },
  { name: 'Customer portal', role: 'Task submission & monitoring', status: 'Operational' },
  { name: 'Worker network', role: 'On-device inference', status: 'Operational' },
];
