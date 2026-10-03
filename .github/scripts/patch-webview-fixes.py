#!/usr/bin/env python3
"""
patch-webview-fixes.py: Fixes upstream SafeBrowsing and Prefetch stubs required
specifically when compiling Android WebView in ungoogled-chromium.
"""
import os
import sys
import re

def find_matching_vanadium_tag(target_version, headers):
    import urllib.request, json, re
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)', target_version)
    if not m:
        return 'main'
    major = m.group(1)
    prefix_build = f"{m.group(1)}.{m.group(2)}.{m.group(3)}"
    try:
        url = 'https://api.github.com/repos/GrapheneOS/Vanadium/tags?per_page=100'
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            tags = [t['name'] for t in json.load(resp)]
        build_matches = [t for t in tags if t.startswith(prefix_build)]
        if build_matches:
            return build_matches[0]
        major_matches = [t for t in tags if t.startswith(f"{major}.")]
        if major_matches:
            return major_matches[0]
    except Exception as e:
        print("Notice finding Vanadium tag:", e)
    return 'main'

def apply_fixes(root):
    src = os.path.join(root, 'src')
    if not os.path.isdir(src):
        print(f"Directory {src} not found, skipping.")
        return

    # 1. aw_browser_context.cc (deleted kSafeBrowsingExtendedReportingOptInAllowed)
    cc = os.path.join(src, 'android_webview/browser/aw_browser_context.cc')
    if os.path.exists(cc):
        with open(cc, 'r', encoding='utf-8') as f:
            c = f.read()
        if 'kSafeBrowsingExtendedReportingOptInAllowed' in c:
            c = re.sub(
                r'void AwBrowserContext::SetExtendedReportingAllowed[^{]+{[^}]+}',
                'void AwBrowserContext::SetExtendedReportingAllowed(bool allowed) {}',
                c
            )
            with open(cc, 'w', encoding='utf-8') as f:
                f.write(c)
            print("Fixed: android_webview/browser/aw_browser_context.cc")

    # 2. aw_prefetch_manager.h (missing components/prefs/pref_service.h include)
    pmh = os.path.join(src, 'android_webview/browser/prefetch/aw_prefetch_manager.h')
    if os.path.exists(pmh):
        with open(pmh, 'r', encoding='utf-8') as f:
            c = f.read()
        if 'components/prefs/pref_service.h' not in c:
            c = c.replace('#include "url/gurl.h"', '#include "url/gurl.h"\n#include "components/prefs/pref_service.h"')
            with open(pmh, 'w', encoding='utf-8') as f:
                f.write(c)
            print("Fixed: android_webview/browser/prefetch/aw_prefetch_manager.h")

    # 3. trigger_manager.cc (SafeBrowsing reporting checks)
    tm = os.path.join(src, 'components/safe_browsing/content/browser/triggers/trigger_manager.cc')
    if os.path.exists(tm):
        with open(tm, 'r', encoding='utf-8') as f:
            c = f.read()
        if 'IsExtendedReportingOptInAllowed' in c:
            c = c.replace('IsExtendedReportingOptInAllowed(pref_service)', 'false')
            c = c.replace('IsExtendedReportingEnabled(pref_service)', 'false')
            with open(tm, 'w', encoding='utf-8') as f:
                f.write(c)
            print("Fixed: components/safe_browsing/content/browser/triggers/trigger_manager.cc")

    # 4. remote_database_manager.cc (RealTimeUrlChecksAllowlist linker error)
    rdm = os.path.join(src, 'components/safe_browsing/android/remote_database_manager.cc')
    if os.path.exists(rdm):
        with open(rdm, 'r', encoding='utf-8') as f:
            c = f.read()
        target = 'IsInAllowlistResult match_result ='
        if target in c:
            idx = c.find(target)
            end_idx = c.find('/*logging_details=*/std::nullopt));', idx)
            if end_idx != -1:
                end_stmt = end_idx + len('/*logging_details=*/std::nullopt));')
                c = c[:idx] + 'ui_task_runner()->PostTask(FROM_HERE, base::BindOnce(std::move(callback), /*url_on_high_confidence_allowlist=*/false, /*logging_details=*/std::nullopt));' + c[end_stmt:]
                with open(rdm, 'w', encoding='utf-8') as f:
                    f.write(c)
                print("Fixed: components/safe_browsing/android/remote_database_manager.cc")

    # 5. aw_url_loader_throttle_provider.cc (RendererURLLoaderThrottle linker error)
    tp = os.path.join(src, 'android_webview/renderer/aw_url_loader_throttle_provider.cc')
    if os.path.exists(tp):
        with open(tp, 'r', encoding='utf-8') as f:
            c = f.read()
        if 'RendererURLLoaderThrottle' in c:
            c = re.sub(
                r'throttles\.emplace_back\([^;]+RendererURLLoaderThrottle[^;]+\);',
                '// SafeBrowsing is stripped in ungoogled-chromium',
                c,
                flags=re.DOTALL
            )
            with open(tp, 'w', encoding='utf-8') as f:
                f.write(c)
            print("Fixed: android_webview/renderer/aw_url_loader_throttle_provider.cc")

    # 6. Apply Vanadium's NetworkAnonymizationKey preconnector patch dynamically
    apc = os.path.join(src, 'android_webview/browser/aw_preconnector.cc')
    if os.path.exists(apc):
        with open(apc, 'r', encoding='utf-8') as f:
            c = f.read()
        if 'net::NetworkAnonymizationKey::CreateSameSite' not in c:
            applied = False
            try:
                import urllib.request, json, subprocess, tempfile
                
                target_ver = os.environ.get('UPSTREAM_TAG', '')
                if not target_ver:
                    bc = os.path.join(root, '.build_config')
                    if os.path.exists(bc):
                        with open(bc, 'r') as bcf:
                            for line in bcf:
                                if line.startswith('chromium_version='):
                                    target_ver = line.strip().split('=')[1]
                
                headers = {'User-Agent': 'vanadium-fetcher'}
                gh_token = os.environ.get('GH_TOKEN', '')
                if gh_token:
                    headers['Authorization'] = f'Bearer {gh_token}'
                
                v_tag = find_matching_vanadium_tag(target_ver, headers)
                print(f"Matched Vanadium release tag: {v_tag} for Chromium version: {target_ver}")
                
                api_url = f'https://api.github.com/repos/GrapheneOS/Vanadium/contents/patches?ref={v_tag}'
                req = urllib.request.Request(api_url, headers=headers)
                with urllib.request.urlopen(req) as resp:
                    p_files = json.load(resp)
                matches = [f for f in p_files if 'networkanonymizationkey' in f.get('name', '').lower()]
                if matches:
                    p_url = matches[0]['download_url']
                    print(f"Dynamically discovered Vanadium patch: {matches[0]['name']}")
                    with urllib.request.urlopen(urllib.request.Request(p_url, headers=headers)) as p_resp:
                        p_data = p_resp.read()
                    temp_p = os.path.join(tempfile.gettempdir(), 'vanadium_precon.patch')
                    with open(temp_p, 'wb') as pf:
                        pf.write(p_data)
                    res = subprocess.run(
                        ['patch', '-p1', '--ignore-whitespace', '--forward', '-d', src, '-i', temp_p],
                        capture_output=True,
                        text=True
                    )
                    if res.returncode == 0 or 'reversed' in res.stdout or 'already applied' in res.stdout:
                        print(f"Successfully applied dynamic Vanadium patch {matches[0]['name']} to aw_preconnector.cc")
                        applied = True
            except Exception as e:
                print("Notice fetching Vanadium patch dynamically:", e)

            # Fallback if network or patch tool failed
            if not applied:
                if '#include "net/base/schemeful_site.h"' not in c:
                    c = c.replace(
                        '#include "net/base/network_anonymization_key.h"',
                        '#include "net/base/network_anonymization_key.h"\n#include "net/base/schemeful_site.h"'
                    )
                old_precon = 'net::NetworkAnonymizationKey key = net::NetworkAnonymizationKey();'
                new_precon = 'net::NetworkAnonymizationKey key =\n      net::NetworkAnonymizationKey::CreateSameSite(net::SchemefulSite(url));'
                if old_precon in c:
                    c = c.replace(old_precon, new_precon)
                    with open(apc, 'w', encoding='utf-8') as f:
                        f.write(c)
                    print("Applied fallback preconnector fix to aw_preconnector.cc")

if __name__ == '__main__':
    ugc_work = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('UGC_WORK', '/mnt/ugc')
    apply_fixes(ugc_work)
