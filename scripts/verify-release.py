#!/usr/bin/env python3
"""Read-only checks for a Developer ID app with Sparkle updates."""
import argparse
import base64
import pathlib
import plistlib
import subprocess
from urllib.parse import urlparse


def require(condition, message):
    if not condition:
        raise SystemExit(f'FAIL: {message}')


parser = argparse.ArgumentParser()
parser.add_argument('app', type=pathlib.Path)
args = parser.parse_args()
contents = args.app / 'Contents'
info = plistlib.loads((contents / 'Info.plist').read_bytes())
require(info['CFBundleIdentifier'] == 'com.goldenrabbit.ohmygrid', 'Wrong bundle identifier')
require(info.get('LSUIElement') is True, 'Menu-bar app flag missing')
require(info.get('CFBundleVersion') and info.get('CFBundleShortVersionString'), 'Version missing')
require(info.get('SUEnableAutomaticChecks') is True, 'Automatic updates disabled')
feed = urlparse(info.get('SUFeedURL', ''))
require(feed.scheme == 'https' and feed.hostname, 'An HTTPS update feed is required')
try:
    public_key = base64.b64decode(info.get('SUPublicEDKey', ''), validate=True)
except ValueError:
    raise SystemExit('FAIL: Invalid Sparkle public key')
require(len(public_key) == 32, 'Sparkle Ed25519 public key missing or invalid')
resources = contents / 'Resources'
require((resources / 'ko.lproj' / 'Localizable.strings').is_file(), 'Korean localization missing')
binary = contents / 'MacOS' / info['CFBundleExecutable']
require(b'https://github.com/Canine89/oh-my-grid/blob/main/PRIVACY.md' in binary.read_bytes(), 'Privacy URL missing')
links = subprocess.check_output(['otool', '-L', str(binary)], text=True)
require('Sparkle.framework' in links, 'Sparkle updater not linked')
require((contents / 'Frameworks' / 'Sparkle.framework').is_dir(), 'Sparkle framework not embedded')
print('PASS: Developer ID / Sparkle release bundle checks')
