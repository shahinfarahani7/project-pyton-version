from __future__ import annotations

from edgemint.models.errors import model_error


def admit_chunk_download(
    *,
    last_chunk_index: int,
    chunk_index: int,
    chunk_sha256: str,
    expected_sha256: str,
) -> int:
    if chunk_index != last_chunk_index + 1:
        raise model_error("MODEL_DIGEST_MISMATCH", detail="chunk replay or out-of-order download")
    if chunk_sha256 != expected_sha256:
        raise model_error("MODEL_DIGEST_MISMATCH", detail="corrupt chunk")
    return chunk_index


def reject_downgrade(*, installed_version_rank: int, candidate_version_rank: int) -> None:
    if candidate_version_rank < installed_version_rank:
        raise model_error("MODEL_SIGNATURE_INVALID", detail="downgrade blocked")
