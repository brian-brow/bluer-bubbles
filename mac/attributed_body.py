from typing import Optional


def extract_text_from_attributed_body(blob: Optional[bytes]) -> Optional[str]:
    """
    Extract plain text from an attributedBody blob (typedstream format).
    Since macOS Ventura, message text may be stored here instead of
    the `text` column for styled/rich messages.

    Returns None if there's nothing to extract (empty blob, no
    NSString/NSMutableString marker found, or malformed data).
    """
    if not blob:
        return None

    marker = b"NSString"
    idx = blob.find(marker)
    if idx == -1:
        marker = b"NSMutableString"
        idx = blob.find(marker)
    if idx == -1:
        return None

    idx += len(marker) + 5
    if idx >= len(blob):
        return None

    if blob[idx] == 0x81:
        if idx + 3 > len(blob):
            return None
        length = int.from_bytes(blob[idx + 1:idx + 3], "little")
        idx += 3
    elif blob[idx] == 0x82:
        if idx + 4 > len(blob):
            return None
        length = int.from_bytes(blob[idx + 1:idx + 4], "little")
        idx += 4
    else:
        length = blob[idx]
        idx += 1

    if length <= 0 or idx + length > len(blob):
        return None

    try:
        return blob[idx:idx + length].decode("utf-8")
    except UnicodeDecodeError:
        try:
            return blob[idx:idx + length].decode("utf-8", errors="replace")
        except Exception:
            return None
