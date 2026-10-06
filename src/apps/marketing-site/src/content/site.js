export const navLinks = [
  { name: 'how-it-works', label: 'How it works' },
  { name: 'use-cases', label: 'Use cases' },
  { name: 'pricing', label: 'Pricing' },
  { name: 'security', label: 'Security' },
  { name: 'workers', label: 'Workers' },
  { name: 'developers', label: 'Developers' },
];

export const hero = {
  eyebrow: 'Edge-first AI inference',
  title: 'Run AI workloads where your policy allows — with a quote before every task.',
  titleHighlight: 'a quote',
  subtitle:
    'EdgeMint routes document, vision, and language tasks to a verified edge worker network first, with explicit cloud fallback, EUR-denominated billing, and a full audit trail for regulated teams.',
  primaryCta: { label: 'Talk to sales', to: 'contact' },
  secondaryCta: { label: 'View documentation', to: 'docs' },
};

export const stats = [
  { value: '60+', label: 'Task types in catalog', icon: '⬡' },
  { value: 'EUR', label: 'Quote-before-run billing', icon: '€' },
  { value: 'Edge', label: 'Preferred execution path', icon: '◈' },
  { value: 'Audit', label: 'Immutable quote & event trail', icon: '⛨' },
];

export const trustBadges = [
  { icon: '⛨', label: 'Signed models' },
  { icon: '€', label: 'Quote-before-run' },
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
    body: 'Workloads run on opted-in devices when policy and SLA allow. Cloud fallback is never silent — reasons and costs are recorded.',
  },
  {
    icon: '€',
    title: 'Deterministic pricing',
    body: 'Every task receives an immutable quote with rule trace before execution. No surprise line items after the fact.',
  },
  {
    icon: '⛨',
    title: 'Verification you can buy up to',
    body: 'From standard inference through consensus and human review — choose the quality tier that matches your risk profile.',
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
    title: 'Receive a quote',
    body: 'EdgeMint returns a deterministic EUR quote with policy hash, verification tier, and execution route before work begins.',
  },
  {
    step: '03',
    title: 'Edge execution',
    body: 'An available worker picks up the assignment, runs signed on-device models, and streams lifecycle events to your workspace.',
  },
  {
    step: '04',
    title: 'Result & audit',
    body: 'Structured output lands in your portal or webhook. Every attempt, revision, and billing event stays in the ledger.',
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

export const pricingRows = [
  { task: 'Document OCR', measure: 'per page', price: '€0.0025' },
  { task: 'Structured extract', measure: 'per document', price: '€0.020' },
  { task: 'Document verify', measure: 'per document', price: '€0.012' },
  { task: 'Image classify', measure: 'per image', price: '€0.0015' },
  { task: 'Image detect', measure: 'per image', price: '€0.004' },
  { task: 'Vision analyze', measure: 'per request', price: '€0.035' },
  { task: 'Audio transcribe', measure: 'per 60 sec', price: '€0.009' },
  { task: 'Text translate', measure: 'per 1k chars', price: '€0.003' },
  { task: 'Text generate', measure: 'per 1k tokens', price: '€0.0065' },
  { task: 'Text embedding', measure: 'per 1k tokens', price: '€0.001' },
];

export const taskFeed = [
  { task: 'document.ocr', file: 'invoice-2291.pdf', meta: 'quote €0.0025 · edge worker', status: 'ok' },
  { task: 'text.summarize', file: 'board-minutes.txt', meta: 'quote locked · edge worker', status: 'ok' },
  { task: 'document.verify', file: 'id-scan.png', meta: 'held · region policy EU-only', status: 'held' },
  { task: 'image.classify', file: 'shelf-photo.jpg', meta: 'quote €0.0015 · edge worker', status: 'ok' },
  { task: 'text.translate', file: 'terms-de.txt', meta: 'cloud fallback · reason recorded', status: 'ok' },
  { task: 'document.ocr', file: 'receipt-118.jpg', meta: 'consensus tier · 2 workers', status: 'ok' },
];

export const quoteSample = [
  '{',
  '  "task_type": "document.ocr",',
  '  "quote": { "amount": "0.0025", "currency": "EUR" },',
  '  "route": "edge_preferred",',
  '  "verification": "standard",',
  '  "fallback": "allowed_with_reason",',
  '  "policy_hash": "sha256:9f2c…e41a"',
  '}',
];

export const taskCards = [
  { glyph: 'OCR', title: 'Document OCR', body: 'Invoices, receipts, and forms to structured text.', price: '€0.0025 per page', to: 'models' },
  { glyph: 'IMG', title: 'Image classify', body: 'Catalog tagging and safety checks on images.', price: '€0.0015 per image', to: 'models' },
  { glyph: 'TXT', title: 'Text translate', body: 'Contracts, tickets, and support text across languages.', price: '€0.003 per 1k chars', to: 'models' },
];

export const capabilityChips = [
  { icon: '€', label: 'Immutable quotes' },
  { icon: '⌖', label: 'Region policies' },
  { icon: '⚯', label: 'Signed webhooks' },
  { icon: '⛨', label: 'Signed models' },
  { icon: '◎', label: 'Verification tiers' },
  { icon: '⛓', label: 'Hash-chained audit log' },
  { icon: '↻', label: 'Idempotent creates' },
  { icon: '⇄', label: 'Replay & dead-letter' },
];

export const portalNav = ['Tasks', 'Quotes', 'Workers', 'Billing', 'Audit log'];

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

export const pricingNotes = [
  'Prices from published PriceBook public-eur-2026q3-v2. Final quotes include plan, priority, verification, and execution-policy modifiers.',
  'Enterprise committed capacity and dedicated pools available on request.',
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
    body: 'Cloud execution only when your policy permits. Fallback reason and incremental cost are recorded on every task.',
  },
  {
    title: 'Compliance-ready',
    body: 'GDPR DPIA checklist, DPA/subprocessor registry, hash-chained audit logs, and store-review evidence packs.',
  },
];

export const workerPoints = [
  'Explicit availability toggle — tasks run only while you opt in.',
  'Battery, Wi-Fi, and thermal controls stay under your settings.',
  'Rewards shown in EUR before participation. No guaranteed income.',
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
    body: '141-operation OpenAPI contract covering task create, quote, lifecycle, webhooks, and workspace administration.',
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
    title: 'Pricing & quotes',
    body: 'Immutable EUR quotes before execution. Published unit rates with plan and verification modifiers.',
    links: [{ label: 'Pricing table', to: 'pricing' }],
  },
];

export const statusComponents = [
  { name: 'API Gateway', role: 'Public REST & portal API', status: 'Operational' },
  { name: 'Worker Registry', role: 'Assignment routing & lifecycle', status: 'Operational' },
  { name: 'Event delivery', role: 'SSE & webhook outbox', status: 'Operational' },
  { name: 'Customer portal', role: 'Task submission & monitoring', status: 'Operational' },
  { name: 'Worker network', role: 'On-device inference', status: 'Operational' },
];
