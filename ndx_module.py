"""
NDX Index File Module

This module provides functions for reading and writing dBase NDX index files.
NDX files are B-tree indexes used by dBase III/IV/V.
"""

import struct
import os
from dataclasses import dataclass
from typing import List, Tuple, Optional

# Constants
NDX_BLOCK_SIZE = 512
NDX_MAX_KEYS = 64
NDX_MAX_KEY_LEN = 80


@dataclass
class NDXHeader:
    """Represents the header of an NDX index file."""
    root_block: int = 0      # Root node block number
    eof_block: int = 0       # End of file block number
    key_len: int = 0         # Key length in bytes
    keys_max: int = 0        # Maximum keys per node
    group_len: int = 0       # Group length (key + pointers)
    expr: str = ''           # Index expression


@dataclass
class NDXNode:
    """Represents a node in the NDX B-tree."""
    num_keys: int = 0                    # Number of keys in this node
    keys: List[str] = None               # Key values
    childs: List[int] = None             # Child block pointers
    recnos: List[int] = None             # Record numbers
    last_child: int = 0                  # Last child pointer
    
    def __post_init__(self):
        if self.keys is None:
            self.keys = []
        if self.childs is None:
            self.childs = []
        if self.recnos is None:
            self.recnos = []


def _get_word_le(buf: bytes, pos: int) -> int:
    """Get a 16-bit little-endian word from buffer."""
    return struct.unpack_from('<H', buf, pos)[0]


def _get_long_le(buf: bytes, pos: int) -> int:
    """Get a 32-bit little-endian long from buffer."""
    return struct.unpack_from('<I', buf, pos)[0]


def _valid_layout(key_len: int, keys_max: int, group_len: int) -> bool:
    """
    Validate NDX layout parameters.
    
    Args:
        key_len: Key length in bytes
        keys_max: Maximum keys per node
        group_len: Group length (key + pointers)
        
    Returns:
        True if layout is valid
    """
    if key_len <= 0 or key_len > 255:
        return False
    if keys_max <= 0 or keys_max > 255:
        return False
    if group_len < key_len + 8:
        return False
    if (4 + (keys_max * group_len) + 4) > NDX_BLOCK_SIZE:
        return False
    return True


def ndx_read_header(filename: str) -> Optional[NDXHeader]:
    """
    Read the header from an NDX index file.
    
    Supports both V1 (dBase III) and V2 (dBase IV) formats:
    - V1: 16-bit block pointers at offset 1, layout at offset 7
    - V2: 32-bit block pointers at offset 1, layout at offset 13
    
    Args:
        filename: Path to the NDX file
        
    Returns:
        NDXHeader object or None if invalid
    """
    try:
        with open(filename, 'rb') as f:
            buf = f.read(NDX_BLOCK_SIZE)
            if len(buf) < NDX_BLOCK_SIZE:
                return None
            
            # Try V1 format (dBase III)
            v1_key_len = _get_word_le(buf, 6)      # Offset 7 in Pascal (1-based)
            v1_keys_max = _get_word_le(buf, 8)     # Offset 9
            v1_group_len = _get_word_le(buf, 10)   # Offset 11
            v1_ok = _valid_layout(v1_key_len, v1_keys_max, v1_group_len)
            
            # Try V2 format (dBase IV)
            v2_key_len = _get_word_le(buf, 12)     # Offset 13
            v2_keys_max = _get_word_le(buf, 14)    # Offset 15
            v2_group_len = _get_word_le(buf, 18)   # Offset 19
            v2_ok = _valid_layout(v2_key_len, v2_keys_max, v2_group_len)
            
            header = NDXHeader()
            
            # Prefer V2 if both are valid but V1 is not
            if v2_ok and not v1_ok:
                # V2 format (dBase IV)
                header.root_block = _get_long_le(buf, 0)    # Offset 1
                header.eof_block = _get_long_le(buf, 4)     # Offset 5
                header.key_len = v2_key_len
                header.keys_max = v2_keys_max
                header.group_len = v2_group_len
                expr_off = 24  # Offset 25 in Pascal
            elif v1_ok:
                # V1 format (dBase III)
                header.root_block = _get_word_le(buf, 0)    # Offset 1
                header.eof_block = _get_word_le(buf, 4)     # Offset 5
                header.key_len = v1_key_len
                header.keys_max = v1_keys_max
                header.group_len = v1_group_len
                expr_off = 16  # Offset 17 in Pascal
            else:
                return None
            
            # Read expression (null-terminated string)
            expr_bytes = []
            i = expr_off
            while i < NDX_BLOCK_SIZE and len(expr_bytes) < 80:
                b = buf[i]
                if b == 0:
                    break
                expr_bytes.append(b)
                i += 1
            
            header.expr = bytes(expr_bytes).decode('latin-1', errors='replace')
            
            return header
            
    except FileNotFoundError:
        return None


def ndx_read_node(filename: str, block: int, header: NDXHeader) -> Optional[NDXNode]:
    """
    Read a node from an NDX index file.
    
    Args:
        filename: Path to the NDX file
        block: Block number to read
        header: NDX header with layout information
        
    Returns:
        NDXNode object or None if error
    """
    try:
        with open(filename, 'rb') as f:
            f.seek(block * NDX_BLOCK_SIZE)
            buf = f.read(NDX_BLOCK_SIZE)
            if len(buf) < NDX_BLOCK_SIZE:
                return None
            
            node = NDXNode()
            node.num_keys = _get_word_le(buf, 0)  # Offset 1 in Pascal
            
            if node.num_keys > header.keys_max:
                node.num_keys = header.keys_max
            
            # Read keys, child pointers, and record numbers
            for i in range(node.num_keys):
                offs = 4 + (i * header.group_len)  # Offset 5 in Pascal
                
                child = _get_long_le(buf, offs)
                recno = _get_long_le(buf, offs + 4)
                
                # Read key string
                key_bytes = buf[offs + 8 : offs + 8 + header.key_len]
                key = key_bytes.decode('latin-1', errors='replace')
                
                node.childs.append(child)
                node.recnos.append(recno)
                node.keys.append(key)
            
            # Read last child pointer
            offs = 4 + (node.num_keys * header.group_len)
            node.last_child = _get_long_le(buf, offs)
            
            return node
            
    except FileNotFoundError:
        return None


def ndx_is_leaf_node(node: NDXNode) -> bool:
    """
    Check if a node is a leaf node (has no children).
    
    Args:
        node: NDX node to check
        
    Returns:
        True if leaf node (all child pointers are 0)
    """
    for child in node.childs:
        if child != 0:
            return False
    return True


def ndx_clean_key(key: str) -> str:
    """
    Clean a key by replacing null bytes with spaces and trimming.
    
    Args:
        key: Raw key string
        
    Returns:
        Cleaned key string
    """
    return key.replace('\x00', ' ').rstrip()


def ndx_dump_first_entries(filename: str, count: int = 10) -> List[Tuple[int, str]]:
    """
    Dump the first N entries from an NDX index file.
    
    Navigates to the leftmost leaf node and returns the first entries.
    
    Args:
        filename: Path to the NDX file
        count: Number of entries to return
        
    Returns:
        List of (record_number, key) tuples
    """
    header = ndx_read_header(filename)
    if not header:
        return []
    
    # Start at root
    block = header.root_block
    if block <= 0:
        return []
    
    # Navigate to leftmost leaf
    node = ndx_read_node(filename, block, header)
    if not node:
        return []
    
    while block > 0 and not ndx_is_leaf_node(node):
        block = node.childs[0]
        node = ndx_read_node(filename, block, header)
        if not node:
            return []
    
    # Collect first N entries
    entries = []
    for i in range(min(node.num_keys, count)):
        recno = node.recnos[i]
        key = ndx_clean_key(node.keys[i])
        entries.append((recno, key))
    
    return entries


def _normalize_key(key: str, key_len: int) -> str:
    """
    Normalize a key to fixed length, replacing nulls with spaces.
    
    Args:
        key: Key string to normalize
        key_len: Target key length
        
    Returns:
        Normalized key string
    """
    # Truncate if too long
    if len(key) > key_len:
        key = key[:key_len]
    
    # Replace null bytes with spaces
    key = key.replace('\x00', ' ')
    
    # Pad with spaces to key_len
    while len(key) < key_len:
        key += ' '
    
    return key


def _compare_keys(a: str, b: str, key_len: int) -> int:
    """
    Compare two keys byte by byte.
    
    Args:
        a: First key
        b: Second key
        key_len: Key length
        
    Returns:
        -1 if a < b, 0 if a == b, 1 if a > b
    """
    a_norm = _normalize_key(a, key_len)
    b_norm = _normalize_key(b, key_len)
    
    for i in range(key_len):
        if a_norm[i] < b_norm[i]:
            return -1
        elif a_norm[i] > b_norm[i]:
            return 1
    
    return 0


def _descend_to_first_ge(filename: str, header: NDXHeader, key_norm: str) -> Tuple[List[int], List[int], int]:
    """
    Descend the B-tree to find the first entry >= key_norm.
    
    Returns:
        Tuple of (stack, stack_idx, depth) where:
        - stack: List of block numbers in path
        - stack_idx: List of indices within each block
        - depth: Current depth in tree
    """
    stack = []
    stack_idx = []
    depth = 0
    block = header.root_block
    
    while block > 0 and depth < 20:  # Max depth 20
        node = ndx_read_node(filename, block, header)
        if not node:
            break
        
        if ndx_is_leaf_node(node):
            # Leaf node - find first key >= key_norm
            stack.append(block)
            i = 0
            while i < node.num_keys and _compare_keys(node.keys[i], key_norm, header.key_len) < 0:
                i += 1
            stack_idx.append(i)
            depth += 1
            break
        
        # Internal node - find child to descend to
        next_block = node.last_child
        next_idx = node.num_keys  # Default to last child position
        i = 0
        while i < node.num_keys:
            if _compare_keys(key_norm, node.keys[i], header.key_len) <= 0:
                next_block = node.childs[i]
                next_idx = i
                break
            i += 1
        
        stack.append(block)
        stack_idx.append(next_idx)
        depth += 1
        block = next_block
    
    return stack, stack_idx, depth


def _descend_leftmost(filename: str, header: NDXHeader, start_block: int, 
                      stack: List[int], stack_idx: List[int], depth: int) -> Tuple[List[int], List[int], int]:
    """
    Descend to the leftmost leaf from a given block.
    
    Returns:
        Updated (stack, stack_idx, depth)
    """
    block = start_block
    
    while block > 0 and depth < 20:
        node = ndx_read_node(filename, block, header)
        if not node:
            break
        
        stack.append(block)
        stack_idx.append(0)
        depth += 1
        
        if ndx_is_leaf_node(node):
            break
        
        if node.num_keys > 0:
            block = node.childs[0]
        else:
            block = node.last_child
    
    return stack, stack_idx, depth


def _advance_to_successor(filename: str, header: NDXHeader, 
                          stack: List[int], stack_idx: List[int], depth: int) -> Tuple[List[int], List[int], int]:
    """
    Advance to the next entry in the B-tree.
    
    Returns:
        Updated (stack, stack_idx, depth)
    """
    while depth > 0:
        child_pos = stack_idx[depth - 1]
        node = ndx_read_node(filename, stack[depth - 1], header)
        if not node:
            break
        
        if child_pos < node.num_keys:
            next_child_pos = child_pos + 1
            if next_child_pos < node.num_keys:
                next_block = node.childs[next_child_pos]
            else:
                next_block = node.last_child
            
            stack_idx[depth - 1] = next_child_pos
            # Descend leftmost from the next block
            new_stack, new_stack_idx, new_depth = _descend_leftmost(filename, header, next_block, stack[:depth], stack_idx[:depth], depth)
            return new_stack, new_stack_idx, new_depth
        
        depth -= 1
    
    return stack, stack_idx, depth


def _next_entry(filename: str, header: NDXHeader, 
                stack: List[int], stack_idx: List[int], depth: int) -> Tuple[bool, str, int, List[int], List[int], int]:
    """
    Get the next entry from the B-tree.
    
    Returns:
        Tuple of (success, key, recno, updated_stack, updated_stack_idx, updated_depth)
    """
    while depth > 0:
        idx = stack_idx[depth - 1]
        node = ndx_read_node(filename, stack[depth - 1], header)
        if not node:
            break
        
        if ndx_is_leaf_node(node):
            if idx < node.num_keys:
                key_out = node.keys[idx]
                recno_out = node.recnos[idx]
                stack_idx[depth - 1] = idx + 1
                return True, key_out, recno_out, stack, stack_idx, depth
            else:
                depth -= 1
                stack, stack_idx, depth = _advance_to_successor(filename, header, stack, stack_idx, depth)
        else:
            depth -= 1
            stack, stack_idx, depth = _advance_to_successor(filename, header, stack, stack_idx, depth)
    
    return False, '', 0, stack, stack_idx, depth


def _normalize_prefix(prefix: str, key_len: int) -> str:
    """
    Normalize a prefix (replace nulls, truncate if needed, but don't pad).
    
    Args:
        prefix: Prefix string to normalize
        key_len: Maximum key length
        
    Returns:
        Normalized prefix string (not padded)
    """
    # Replace null bytes with spaces
    prefix = prefix.replace('\x00', ' ')
    
    # Truncate if too long
    if len(prefix) > key_len:
        prefix = prefix[:key_len]
    
    return prefix


def _starts_with_key(key_str: str, prefix: str) -> bool:
    """
    Check if a key starts with a prefix.
    
    Args:
        key_str: Key string to check
        prefix: Prefix to match
        
    Returns:
        True if key_str starts with prefix
    """
    if len(prefix) == 0:
        return False
    
    if len(key_str) < len(prefix):
        return False
    
    for i in range(len(prefix)):
        if key_str[i] != prefix[i]:
            return False
    
    return True


def ndx_find_exact(filename: str, search_key: str, max_count: int = 1000) -> List[int]:
    """
    Find all record numbers with exact key match.
    
    Args:
        filename: Path to the NDX file
        search_key: Key to search for
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers matching the key
    """
    header = ndx_read_header(filename)
    if not header:
        return []
    
    # Normalize search key
    key_norm = _normalize_key(search_key, header.key_len)
    
    # Descend to first entry >= search key
    stack, stack_idx, depth = _descend_to_first_ge(filename, header, key_norm)
    
    # Collect all matching entries
    results = []
    
    while len(results) < max_count:
        success, key_out, recno_out, stack, stack_idx, depth = _next_entry(
            filename, header, stack, stack_idx, depth)
        
        if not success:
            break
        
        # Compare with search key
        cmp = _compare_keys(key_out, key_norm, header.key_len)
        if cmp != 0:
            break  # No more matches
        
        if recno_out != 0:
            results.append(recno_out)
    
    return results


def ndx_find_prefix(filename: str, prefix: str, max_count: int = 1000) -> List[int]:
    """
    Find all record numbers where key starts with prefix.
    
    Args:
        filename: Path to the NDX file
        prefix: Prefix to search for
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers where key starts with prefix
    """
    header = ndx_read_header(filename)
    if not header:
        return []
    
    # Normalize prefix (don't pad)
    prefix_norm = _normalize_prefix(prefix, header.key_len)
    
    # Create search key by padding prefix to full key length
    key_norm = _normalize_key(prefix_norm, header.key_len)
    
    # Descend to first entry >= search key
    stack, stack_idx, depth = _descend_to_first_ge(filename, header, key_norm)
    
    # Collect all matching entries
    results = []
    
    while len(results) < max_count:
        success, key_out, recno_out, stack, stack_idx, depth = _next_entry(
            filename, header, stack, stack_idx, depth)
        
        if not success:
            break
        
        # Normalize key_out as prefix (don't pad) for comparison
        key_out_prefix = _normalize_prefix(key_out, header.key_len)
        
        # Check if key starts with prefix
        if not _starts_with_key(key_out_prefix, prefix_norm):
            break  # No more matches
        
        if recno_out != 0:
            results.append(recno_out)
    
    return results


def _make_key8_from_int(value: int) -> bytes:
    """
    Convert an integer to an 8-byte key (as double).
    
    Args:
        value: Integer value
        
    Returns:
        8-byte representation as double
    """
    import struct
    return struct.pack('<d', float(value))  # Little-endian double


def _key_str_to_key8(key_str: str) -> bytes:
    """
    Extract first 8 bytes from a key string.
    
    Args:
        key_str: Key string from NDX
        
    Returns:
        8-byte array
    """
    result = bytearray(8)
    for i in range(min(8, len(key_str))):
        result[i] = ord(key_str[i])
    return bytes(result)


def _compare_key8(a: bytes, b: bytes) -> int:
    """
    Compare two 8-byte keys (byte by byte, from high to low).
    
    Args:
        a: First 8-byte key
        b: Second 8-byte key
        
    Returns:
        -1 if a < b, 0 if a == b, 1 if a > b
    """
    # Compare from byte 7 down to byte 0 (high to low)
    for i in range(7, -1, -1):
        if a[i] < b[i]:
            return -1
        elif a[i] > b[i]:
            return 1
    return 0


def _descend_to_first_ge_number(filename: str, header: NDXHeader, target: bytes) -> Tuple[List[int], List[int], int]:
    """
    Descend the B-tree to find the first numeric entry >= target.
    
    Args:
        filename: NDX filename
        header: NDX header
        target: 8-byte target value
        
    Returns:
        Tuple of (stack, stack_idx, depth)
    """
    stack = []
    stack_idx = []
    depth = 0
    block = header.root_block
    
    while block > 0 and depth < 20:
        node = ndx_read_node(filename, block, header)
        if not node:
            break
        
        if ndx_is_leaf_node(node):
            # Leaf node - find first key >= target
            stack.append(block)
            idx = node.num_keys  # Default to end
            for i in range(node.num_keys):
                key_val = _key_str_to_key8(node.keys[i])
                if _compare_key8(key_val, target) >= 0:
                    idx = i
                    break
            stack_idx.append(idx)
            depth += 1
            break
        
        # Internal node - find child to descend to
        next_block = node.last_child
        next_idx = node.num_keys
        for i in range(node.num_keys):
            key_val = _key_str_to_key8(node.keys[i])
            if _compare_key8(target, key_val) <= 0:
                next_block = node.childs[i]
                next_idx = i
                break
        
        stack.append(block)
        stack_idx.append(next_idx)
        depth += 1
        block = next_block
    
    return stack, stack_idx, depth


def ndx_find_number_exact(filename: str, value: int, max_count: int = 1000) -> List[int]:
    """
    Find all record numbers with exact numeric value match.
    
    Args:
        filename: Path to the NDX file
        value: Integer value to search for
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers matching the value
    """
    header = ndx_read_header(filename)
    if not header:
        return []
    
    if header.key_len < 8:
        return []  # Not a numeric index
    
    # Convert value to 8-byte key
    target = _make_key8_from_int(value)
    
    # Descend to first entry >= target
    stack, stack_idx, depth = _descend_to_first_ge_number(filename, header, target)
    
    # Collect all matching entries
    results = []
    
    while len(results) < max_count:
        success, key_out, recno_out, stack, stack_idx, depth = _next_entry(
            filename, header, stack, stack_idx, depth)
        
        if not success:
            break
        
        # Compare with target
        key_val = _key_str_to_key8(key_out)
        if _compare_key8(key_val, target) != 0:
            break  # No more matches
        
        if recno_out != 0:
            results.append(recno_out)
    
    return results


def ndx_find_number_range(filename: str, min_value: int, max_value: int, max_count: int = 10000) -> List[int]:
    """
    Find all record numbers with numeric values in range [min_value, max_value].
    
    Args:
        filename: Path to the NDX file
        min_value: Minimum value (inclusive)
        max_value: Maximum value (inclusive)
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers in the range
    """
    header = ndx_read_header(filename)
    if not header:
        return []
    
    if header.key_len < 8:
        return []  # Not a numeric index
    
    if min_value > max_value:
        return []
    
    # Convert values to 8-byte keys
    min_key = _make_key8_from_int(min_value)
    max_key = _make_key8_from_int(max_value)
    
    # Descend to first entry >= min_value
    stack, stack_idx, depth = _descend_to_first_ge_number(filename, header, min_key)
    
    # Collect all entries in range
    results = []
    
    while len(results) < max_count:
        success, key_out, recno_out, stack, stack_idx, depth = _next_entry(
            filename, header, stack, stack_idx, depth)
        
        if not success:
            break
        
        # Check if still in range
        key_val = _key_str_to_key8(key_out)
        if _compare_key8(key_val, max_key) > 0:
            break  # Beyond max value
        
        if recno_out != 0:
            results.append(recno_out)
    
    return results


def _gregorian_to_jdn(year: int, month: int, day: int) -> int:
    """
    Convert Gregorian date to Julian Day Number.
    
    Args:
        year: Year
        month: Month (1-12)
        day: Day (1-31)
        
    Returns:
        Julian Day Number
    """
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + 12 * a - 3
    return day + (153 * m + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045


def _date_str_to_jdn(date_str: str) -> int:
    """
    Convert date string to Julian Day Number.
    
    Supports formats:
    - YYYY-MM-DD (e.g., '2022-08-25')
    - YYYYMMDD (e.g., '20220825')
    
    Args:
        date_str: Date string
        
    Returns:
        Julian Day Number
        
    Raises:
        ValueError: If date string is invalid
    """
    s = date_str.strip()
    
    # Try YYYY-MM-DD format
    if len(s) == 10 and s[4] == '-' and s[7] == '-':
        try:
            year = int(s[0:4])
            month = int(s[5:7])
            day = int(s[8:10])
        except ValueError:
            raise ValueError(f"Invalid date format: {date_str}")
    # Try YYYYMMDD format
    elif len(s) == 8:
        try:
            year = int(s[0:4])
            month = int(s[4:6])
            day = int(s[6:8])
        except ValueError:
            raise ValueError(f"Invalid date format: {date_str}")
    else:
        raise ValueError(f"Invalid date format: {date_str}")
    
    # Validate ranges
    if month < 1 or month > 12 or day < 1 or day > 31:
        raise ValueError(f"Invalid date values: {date_str}")
    
    return _gregorian_to_jdn(year, month, day)


def ndx_find_date_exact(filename: str, date_str: str, max_count: int = 1000) -> List[int]:
    """
    Find all record numbers with exact date match.
    
    Args:
        filename: Path to the NDX file
        date_str: Date string in format 'YYYY-MM-DD' or 'YYYYMMDD'
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers matching the date
    """
    try:
        jdn = _date_str_to_jdn(date_str)
    except ValueError:
        return []
    
    return ndx_find_number_exact(filename, jdn, max_count)


def ndx_find_date_range(filename: str, start_date_str: str, end_date_str: str, max_count: int = 10000) -> List[int]:
    """
    Find all record numbers with dates in range [start_date, end_date].
    
    Args:
        filename: Path to the NDX file
        start_date_str: Start date string in format 'YYYY-MM-DD' or 'YYYYMMDD'
        end_date_str: End date string in format 'YYYY-MM-DD' or 'YYYYMMDD'
        max_count: Maximum number of results to return
        
    Returns:
        List of record numbers in the date range
    """
    try:
        jdn_start = _date_str_to_jdn(start_date_str)
        jdn_end = _date_str_to_jdn(end_date_str)
    except ValueError:
        return []
    
    return ndx_find_number_range(filename, jdn_start, jdn_end, max_count)


def ndx_create_index(dbf_filename: str, field_name: str, output_filename: str = None) -> bool:
    """
    Create an NDX index file from a DBF file for a specific field.
    
    Args:
        dbf_filename: Path to the DBF file
        field_name: Name of the field to index
        output_filename: Optional output NDX filename (default: FIELDNAME.NDX)
        
    Returns:
        True if successful, False otherwise
    """
    from dbf_module import dbf_file_open, dbf_file_close, dbf_file_seek_to_first_row, dbf_file_read_row
    
    # Open DBF file
    dbf = dbf_file_open(dbf_filename)
    if not dbf:
        return False
    
    try:
        # Find the field
        field_idx = -1
        field_type = None
        key_len = 0
        
        for i, field in enumerate(dbf.header.fields):
            if field.name.upper() == field_name.upper():
                field_idx = i
                field_type = field.field_type
                key_len = field.length
                break
        
        if field_idx == -1:
            return False
        
        # Support Character, Date, and Numeric fields
        if field_type not in ('C', 'D', 'N'):
            return False
        
        # For numeric and date fields, the index key is always 8 bytes (double)
        if field_type in ('D', 'N'):
            key_len = 8
        
        if key_len <= 0 or key_len > NDX_MAX_KEY_LEN:
            return False
        
        # Calculate NDX parameters
        group_len = key_len + 8
        if group_len % 4 != 0:
            group_len += (4 - (group_len % 4))
        
        keys_max = (NDX_BLOCK_SIZE - 8) // group_len
        if keys_max <= 0 or keys_max > NDX_MAX_KEYS:
            return False
        
        # Read all rows and extract keys
        entries = []
        row_count = dbf.header.record_count
        
        dbf_file_seek_to_first_row(dbf)
        
        for row_idx in range(row_count):
            row = dbf_file_read_row(dbf)
            
            # Check if deleted (first element is '*')
            if len(row) > 0 and row[0] == '*':
                continue
            
            # Get field value (skip deletion marker at index 0)
            # Field indices are offset by 1 because row[0] is the deletion marker
            actual_field_idx = field_idx + 1
            if actual_field_idx < len(row):
                value = row[actual_field_idx]
                if isinstance(value, str):
                    key_str = value.strip()
                else:
                    key_str = str(value).strip()
            else:
                key_str = ''
            
            # For date fields, convert to Julian Day Number
            if field_type == 'D' and key_str:
                try:
                    # Date is stored as YYYYMMDD string
                    if len(key_str) == 8:
                        year = int(key_str[0:4])
                        month = int(key_str[4:6])
                        day = int(key_str[6:8])
                        jdn = _gregorian_to_jdn(year, month, day)
                        # Convert JDN to 8-byte double representation
                        import struct
                        key_bytes = struct.pack('<d', float(jdn))
                        key_norm = key_bytes.decode('latin-1')
                    else:
                        key_norm = '\x00' * key_len
                except (ValueError, IndexError):
                    key_norm = '\x00' * key_len
            elif field_type == 'N':
                try:
                    # Numeric field - convert to 8-byte double
                    import struct
                    if key_str:
                        num_value = float(key_str)
                    else:
                        num_value = 0.0
                    key_bytes = struct.pack('<d', num_value)
                    key_norm = key_bytes.decode('latin-1')
                except (ValueError, IndexError):
                    key_norm = '\x00' * key_len
            else:
                # Normalize key for character fields
                key_norm = _normalize_key(key_str, key_len)
            
            entries.append({
                'key': key_norm,
                'recno': row_idx + 1
            })
        
        # Determine output filename
        if output_filename is None:
            base_name = field_name.upper()[:8]
            output_filename = f"{base_name}.NDX"
        
        # Create the index
        _write_ndx_file(output_filename, entries, key_len, keys_max, group_len, field_name.lower())
        
        return True
        
    finally:
        dbf_file_close(dbf)


def _write_ndx_file(filename: str, entries: List[dict], key_len: int, keys_max: int, 
                    group_len: int, expr: str):
    """
    Write an NDX file with the given entries.
    
    Args:
        filename: Output filename
        entries: List of {'key': str, 'recno': int} entries
        key_len: Key length
        keys_max: Maximum keys per node
        group_len: Group length (key + pointers)
        expr: Index expression
    """
    with open(filename, 'wb') as f:
        if len(entries) == 0:
            # Write empty index
            _write_empty_header(f, key_len, keys_max, group_len, expr)
            return
        
        # Sort entries by key
        # For numeric/date keys (8 bytes), we need to sort by the actual numeric value
        # not the byte representation
        if key_len == 8:
            import struct
            def get_numeric_value(entry):
                try:
                    key_bytes = entry['key'].encode('latin-1')
                    return struct.unpack('<d', key_bytes)[0]
                except:
                    return 0.0
            entries.sort(key=get_numeric_value)
        else:
            entries.sort(key=lambda e: e['key'])
        
        # Build leaf nodes
        leaf_nodes = []
        block = 1
        
        for i in range(0, len(entries), keys_max):
            chunk = entries[i:i + keys_max]
            leaf_nodes.append({
                'block': block,
                'entries': chunk,
                'max_key': chunk[-1]['key']
            })
            block += 1
        
        # Write leaf nodes
        for node in leaf_nodes:
            _write_leaf_node(f, node['block'], node['entries'], key_len, group_len, keys_max)
        
        # Build internal nodes bottom-up
        current_level = leaf_nodes
        child_per_node = keys_max + 1
        
        while len(current_level) > 1:
            next_level = []
            
            for i in range(0, len(current_level), child_per_node):
                chunk = current_level[i:i + child_per_node]
                
                # Create parent node
                parent_entries = []
                child_blocks = []
                
                for j in range(len(chunk) - 1):
                    parent_entries.append({
                        'key': chunk[j]['max_key'],
                        'recno': 0
                    })
                    child_blocks.append(chunk[j]['block'])
                
                last_child = chunk[-1]['block']
                
                next_level.append({
                    'block': block,
                    'entries': parent_entries,
                    'child_blocks': child_blocks,
                    'last_child': last_child,
                    'max_key': chunk[-1]['max_key']
                })
                
                # Write internal node
                _write_internal_node(f, block, parent_entries, child_blocks, last_child, 
                                    key_len, group_len, keys_max)
                block += 1
            
            current_level = next_level
        
        # Write header
        root_block = current_level[0]['block']
        eof_block = block
        _write_header(f, root_block, eof_block, key_len, keys_max, group_len, expr)


def _write_empty_header(f, key_len: int, keys_max: int, group_len: int, expr: str):
    """Write header for empty index."""
    buf = bytearray(NDX_BLOCK_SIZE)
    _set_long_le(buf, 0, 0)  # root_block = 0
    _set_long_le(buf, 4, 1)  # eof_block = 1
    _set_word_le(buf, 12, key_len)
    _set_word_le(buf, 14, keys_max)
    _set_word_le(buf, 18, group_len)
    
    expr_bytes = expr.encode('ascii')
    if len(expr_bytes) > 0:
        buf[24:24+len(expr_bytes)] = expr_bytes
    buf[24 + len(expr_bytes)] = 0
    
    f.seek(0)
    f.write(buf)


def _write_header(f, root_block: int, eof_block: int, key_len: int, keys_max: int, 
                  group_len: int, expr: str):
    """Write NDX header."""
    buf = bytearray(NDX_BLOCK_SIZE)
    _set_long_le(buf, 0, root_block)
    _set_long_le(buf, 4, eof_block)
    _set_word_le(buf, 12, key_len)
    _set_word_le(buf, 14, keys_max)
    _set_word_le(buf, 18, group_len)
    
    expr_bytes = expr.encode('ascii')
    if len(expr_bytes) > 0:
        buf[24:24+len(expr_bytes)] = expr_bytes
    buf[24 + len(expr_bytes)] = 0
    
    f.seek(0)
    f.write(buf)


def _write_leaf_node(f, block: int, entries: List[dict], key_len: int, group_len: int, keys_max: int):
    """Write a leaf node."""
    buf = bytearray(NDX_BLOCK_SIZE)
    
    # Number of keys
    num_keys = len(entries)
    _set_word_le(buf, 0, num_keys)
    
    # Write entries - layout is [child][recno][key][padding]
    # Each entry is group_len bytes total
    pos = 4
    for entry in entries:
        # Child pointer (4 bytes, always 0 for leaf)
        _set_long_le(buf, pos, 0)
        
        # Record number (4 bytes, little-endian)
        _set_long_le(buf, pos + 4, entry['recno'])
        
        # Key (key_len bytes)
        key_str = entry['key']
        if isinstance(key_str, bytes):
            key_bytes = key_str
        else:
            key_bytes = key_str.encode('latin-1', errors='replace')
        buf[pos + 8:pos + 8 + len(key_bytes)] = key_bytes
        
        # Advance by full group_len (includes padding)
        pos += group_len
    
    # Last child pointer (always 0 for leaf)
    _set_long_le(buf, pos, 0)
    
    f.seek(block * NDX_BLOCK_SIZE)
    f.write(buf)


def _write_internal_node(f, block: int, entries: List[dict], child_blocks: List[int], 
                        last_child: int, key_len: int, group_len: int, keys_max: int):
    """Write an internal node."""
    buf = bytearray(NDX_BLOCK_SIZE)
    
    # Number of keys
    num_keys = len(entries)
    _set_word_le(buf, 0, num_keys)
    
    # Write entries - layout is [child][recno][key][padding]
    # Each entry is group_len bytes total
    pos = 4
    for i, entry in enumerate(entries):
        # Child pointer
        _set_long_le(buf, pos, child_blocks[i])
        
        # Record number (always 0 for internal nodes)
        _set_long_le(buf, pos + 4, 0)
        
        # Key (key_len bytes)
        key_str = entry['key']
        if isinstance(key_str, bytes):
            key_bytes = key_str
        else:
            key_bytes = key_str.encode('latin-1', errors='replace')
        buf[pos + 8:pos + 8 + len(key_bytes)] = key_bytes
        
        # Advance by full group_len (includes padding)
        pos += group_len
    
    # Last child pointer
    _set_long_le(buf, pos, last_child)
    
    f.seek(block * NDX_BLOCK_SIZE)
    f.write(buf)


def _set_word_le(buf: bytearray, offset: int, value: int):
    """Set a 16-bit little-endian word."""
    buf[offset] = value & 0xFF
    buf[offset + 1] = (value >> 8) & 0xFF


def _set_long_le(buf: bytearray, offset: int, value: int):
    """Set a 32-bit little-endian long."""
    buf[offset] = value & 0xFF
    buf[offset + 1] = (value >> 8) & 0xFF
    buf[offset + 2] = (value >> 16) & 0xFF
    buf[offset + 3] = (value >> 24) & 0xFF


__all__ = [
    'NDXHeader', 'NDXNode',
    'ndx_read_header', 'ndx_read_node',
    'ndx_is_leaf_node', 'ndx_clean_key',
    'ndx_dump_first_entries',
    'ndx_find_exact', 'ndx_find_prefix', 
    'ndx_find_number_exact', 'ndx_find_number_range',
    'ndx_find_date_exact', 'ndx_find_date_range',
    'ndx_create_index',
    'NDX_BLOCK_SIZE', 'NDX_MAX_KEYS', 'NDX_MAX_KEY_LEN'
]
