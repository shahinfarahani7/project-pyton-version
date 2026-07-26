# Retention and Deletion

The effective retention is the strictest applicable value from legal hold, DataPolicy, TaskType, workspace contract and user request. Worker temporary payloads are deleted after server acknowledgement or lease termination. Customer deletion creates a tracked erasure job, removes/cryptographically erases payloads and preserves only legally required financial/security records with identifiers minimized. Backups age out according to the backup retention schedule; deletion completion discloses that delay.
