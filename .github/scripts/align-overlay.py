#!/usr/bin/env python3
"""
align-overlay.py: Aligns WebView runtime resource overlay APK (res/xml/config_webview_packages.xml)
with the signing certificate of the target TrichromeWebView APK.
"""

import sys
import os
import io
import re
import struct
import base64
import zipfile
import subprocess
import tempfile
import shutil

def extract_cert_from_apk(apk_path):
    """Extract DER certificate as base64 string from an APK using keytool or direct APK parsing."""
    # Method 1: Try keytool
    try:
        res = subprocess.run(
            ['keytool', '-printcert', '-jarfile', apk_path, '-rfc'],
            capture_output=True,
            text=True,
            check=True
        )
        m = re.search(r'-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----', res.stdout)
        if m:
            cert_b64 = re.sub(r'\s+', '', m.group(1))
            if cert_b64:
                return cert_b64
    except Exception:
        pass

    # Method 2: Try v1 signature (META-INF/*.RSA, *.DSA, *.EC)
    try:
        with zipfile.ZipFile(apk_path, 'r') as z:
            for name in z.namelist():
                if name.startswith('META-INF/') and (name.endswith('.RSA') or name.endswith('.DSA') or name.endswith('.EC')):
                    data = z.read(name)
                    try:
                        from cryptography.hazmat.primitives.serialization import pkcs7, Encoding
                        certs = pkcs7.load_der_pkcs7_certificates(data)
                        if certs:
                            der = certs[0].public_bytes(Encoding.DER)
                            return base64.b64encode(der).decode('ascii')
                    except Exception:
                        pass
    except Exception:
        pass

    # Method 3: Parse APK Signing Block (v2 / v3)
    try:
        with open(apk_path, 'rb') as f:
            f.seek(0, 2)
            size = f.tell()
            search_len = min(size, 65558)
            f.seek(size - search_len)
            data = f.read(search_len)
            eocd_pos = data.rfind(b'PK\x05\x06')
            if eocd_pos != -1:
                cd_offset = struct.unpack_from('<I', data, eocd_pos + 16)[0]
                f.seek(cd_offset - 16)
                if f.read(16) == b'APK Sig Block 42':
                    f.seek(cd_offset - 24)
                    block_size = struct.unpack('<Q', f.read(8))[0]
                    f.seek(cd_offset - 8 - block_size)
                    block_data = f.read(block_size)
                    p = 0
                    while p < len(block_data) - 24:
                        pair_len = struct.unpack_from('<Q', block_data, p)[0]
                        p += 8
                        pair_id = struct.unpack_from('<I', block_data, p)[0]
                        pair_val = block_data[p + 4 : p + pair_len]
                        p += pair_len
                        # ID 0x7109871a (v2) or 0xf05368c0 (v3)
                        if pair_id in (0x7109871a, 0xf05368c0):
                            sd_pos = 12
                            digests_len = struct.unpack_from('<I', pair_val, sd_pos)[0]
                            sd_pos += 4 + digests_len
                            certs_len = struct.unpack_from('<I', pair_val, sd_pos)[0]
                            sd_pos += 4
                            cert_len = struct.unpack_from('<I', pair_val, sd_pos)[0]
                            cert_der = pair_val[sd_pos + 4 : sd_pos + 4 + cert_len]
                            return base64.b64encode(cert_der).decode('ascii')
    except Exception:
        pass

    return None

def update_axml_strings(axml_data, replacements):
    """Update string pool of an AXML binary file while preserving all other chunks."""
    header_type, header_size, file_size = struct.unpack_from('<HHI', axml_data, 0)
    sp_type, sp_header_size, sp_size = struct.unpack_from('<HHI', axml_data, 8)
    string_count, style_count, flags, strings_start, styles_start = struct.unpack_from('<IIIII', axml_data, 16)

    offsets = [struct.unpack_from('<I', axml_data, 36 + i * 4)[0] for i in range(string_count)]
    str_base = 8 + strings_start
    strings = []
    for off in offsets:
        p = str_base + off
        u16len = struct.unpack_from('<H', axml_data, p)[0]
        p += 2
        strings.append(axml_data[p:p + u16len * 2].decode('utf-16le', errors='replace'))

    for idx, new_val in replacements.items():
        if 0 <= idx < len(strings):
            strings[idx] = new_val

    new_str_bytes = bytearray()
    new_offsets = []
    for s in strings:
        new_offsets.append(len(new_str_bytes))
        s_encoded = s.encode('utf-16le')
        s_len = len(s)
        if s_len >= 0x8000:
            hi = 0x8000 | ((s_len >> 16) & 0x7fff)
            lo = s_len & 0xffff
            new_str_bytes.extend(struct.pack('<HH', hi, lo))
        else:
            new_str_bytes.extend(struct.pack('<H', s_len))
        new_str_bytes.extend(s_encoded)
        new_str_bytes.extend(b'\x00\x00')

    # 4-byte alignment padding for string pool data
    pad = (4 - (len(new_str_bytes) % 4)) % 4
    new_str_bytes.extend(b'\x00' * pad)

    new_strings_start = 28 + (string_count * 4) + (style_count * 4)
    new_sp_size = new_strings_start + len(new_str_bytes)

    new_sp = bytearray()
    new_sp.extend(struct.pack('<HHI', sp_type, sp_header_size, new_sp_size))
    new_sp.extend(struct.pack('<IIIII', string_count, style_count, flags, new_strings_start, styles_start))
    for off in new_offsets:
        new_sp.extend(struct.pack('<I', off))
    new_sp.extend(new_str_bytes)

    xml_nodes = axml_data[8 + sp_size :]
    new_file_size = 8 + len(new_sp) + len(xml_nodes)
    new_header = struct.pack('<HHI', header_type, header_size, new_file_size)

    return bytes(new_header + new_sp + xml_nodes)

def find_target_indices(axml_data, target_package):
    """Find description string index and signature string index for a target package."""
    sp_type, sp_header_size, sp_size = struct.unpack_from('<HHI', axml_data, 8)
    string_count, style_count, flags, strings_start, styles_start = struct.unpack_from('<IIIII', axml_data, 16)
    offsets = [struct.unpack_from('<I', axml_data, 36 + i * 4)[0] for i in range(string_count)]
    str_base = 8 + strings_start
    strings = []
    for off in offsets:
        p = str_base + off
        u16len = struct.unpack_from('<H', axml_data, p)[0]
        p += 2
        strings.append(axml_data[p:p + u16len * 2].decode('utf-16le', errors='replace'))

    desc_idx = None
    sig_idx = None
    in_target = False

    offset = 8 + sp_size
    while offset < len(axml_data):
        ctype, hsize, csize = struct.unpack_from('<HHI', axml_data, offset)
        if ctype == 0x0102: # START_TAG
            ns_idx, name_idx, a_start, a_sz, a_cnt, id_i, cl_i, st_i = struct.unpack_from('<IIHHHHHH', axml_data, offset + 16)
            tag_name = strings[name_idx] if name_idx < len(strings) else ''
            if tag_name == 'webviewprovider':
                attr_offset = offset + 16 + a_start
                pkg_val = None
                cur_desc = None
                for a in range(a_cnt):
                    ans, aname, aval, avsize, avres0, avtype, avdata = struct.unpack_from('<IIIHBBI', axml_data, attr_offset + a * a_sz)
                    attr_name = strings[aname] if aname < len(strings) else ''
                    if attr_name == 'packageName':
                        pkg_val = strings[aval] if aval < len(strings) else ''
                    elif attr_name == 'description':
                        cur_desc = aval
                if pkg_val == target_package:
                    in_target = True
                    desc_idx = cur_desc
        elif ctype == 0x0104: # TEXT
            if in_target and sig_idx is None:
                str_i = struct.unpack_from('<I', axml_data, offset + 16)[0]
                sig_idx = str_i
        elif ctype == 0x0103: # END_TAG
            ns_idx, name_idx = struct.unpack_from('<II', axml_data, offset + 16)
            if name_idx < len(strings) and strings[name_idx] == 'webviewprovider' and in_target:
                in_target = False
                break
        offset += csize

    return desc_idx, sig_idx

def align_overlay(overlay_apk_path, source_cert_or_apk, new_description='Ungoogled Chromium WebView', target_package='com.android.webview'):
    if not os.path.exists(overlay_apk_path):
        raise FileNotFoundError(f"Overlay APK not found: {overlay_apk_path}")

    # Determine certificate
    if os.path.exists(source_cert_or_apk):
        print(f"Extracting certificate from {source_cert_or_apk}...")
        cert_b64 = extract_cert_from_apk(source_cert_or_apk)
        if not cert_b64:
            raise ValueError(f"Failed to extract certificate from {source_cert_or_apk}")
    else:
        # Direct base64 string provided
        cert_b64 = source_cert_or_apk.strip()

    print(f"Target package: {target_package}")
    print(f"New description: {new_description}")
    print(f"Certificate length (base64): {len(cert_b64)}")

    # Read overlay APK
    temp_dir = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(overlay_apk_path, 'r') as z_in:
            if 'res/xml/config_webview_packages.xml' not in z_in.namelist():
                raise KeyError("res/xml/config_webview_packages.xml not found in overlay APK")

            xml_data = z_in.read('res/xml/config_webview_packages.xml')
            desc_idx, sig_idx = find_target_indices(xml_data, target_package)
            if desc_idx is None or sig_idx is None:
                raise ValueError(f"Could not locate package {target_package} in config_webview_packages.xml")

            print(f"Found {target_package}: description string index={desc_idx}, signature string index={sig_idx}")
            new_xml_data = update_axml_strings(xml_data, {desc_idx: new_description, sig_idx: cert_b64})

            temp_apk = os.path.join(temp_dir, 'aligned_overlay.apk')
            with zipfile.ZipFile(temp_apk, 'w') as z_out:
                for item in z_in.infolist():
                    if item.filename.startswith('META-INF/'):
                        # Exclude old signature files
                        continue

                    new_item = zipfile.ZipInfo(item.filename, item.date_time)
                    new_item.create_system = item.create_system
                    new_item.external_attr = item.external_attr

                    data = new_xml_data if item.filename == 'res/xml/config_webview_packages.xml' else z_in.read(item.filename)

                    # Ensure resources.arsc is stored uncompressed and 4-byte aligned for mmap
                    if item.filename == 'resources.arsc':
                        new_item.compress_type = zipfile.ZIP_STORED
                        current_offset = z_out.fp.tell()
                        header_size = 30 + len(new_item.filename)
                        padding = (4 - ((current_offset + header_size) % 4)) % 4
                        if padding > 0:
                            new_item.extra = b'\x00' * padding
                    else:
                        new_item.compress_type = item.compress_type

                    z_out.writestr(new_item, data)

        # Replace original
        shutil.move(temp_apk, overlay_apk_path)
        print(f"Successfully aligned overlay APK: {overlay_apk_path}")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <overlay_apk> <source_apk_or_cert_b64> [new_description] [target_package]")
        sys.exit(1)

    overlay_apk = sys.argv[1]
    source = sys.argv[2]
    desc = sys.argv[3] if len(sys.argv) > 3 else 'Ungoogled Chromium WebView'
    pkg = sys.argv[4] if len(sys.argv) > 4 else 'com.android.webview'

    align_overlay(overlay_apk, source, desc, pkg)
