#!/usr/bin/env python3
"""
patch-webview-fixes.py: Fixes upstream SafeBrowsing and Prefetch stubs required
specifically when compiling Android WebView in ungoogled-chromium.
"""
import os
import sys
import re

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

if __name__ == '__main__':
    ugc_work = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('UGC_WORK', '/mnt/ugc')
    apply_fixes(ugc_work)
