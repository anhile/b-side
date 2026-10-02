# Releasing

A release is one file, `B-Side-<version>.dmg`: a universal app (Apple
silicon and Intel) signed with Developer ID and the hardened runtime,
notarised by Apple and stapled. A Mac opens it without a Gatekeeper warning.

`scripts/release.sh` does all of it. It needs two things set up once.

## Once on the Mac that releases

Both need membership in the Apple Developer Program.

**1. A Developer ID Application certificate.** In Xcode: Settings → Accounts
→ the team → Manage Certificates → **+** → Developer ID Application. Only
the team's Account Holder can make one. Check that it is there:

```bash
security find-identity -v -p codesigning
```

**2. Notary credentials in the keychain.** Make an app-specific password at
[account.apple.com](https://account.apple.com) (Sign-In and Security →
App-Specific Passwords), then store it; the command asks for the password,
so it is in no file and no shell history:

```bash
xcrun notarytool store-credentials b-side-notary --apple-id <your Apple ID> --team-id <your team ID>
```

The team ID is the ten characters in brackets at the end of the
certificate's name.

## Each release

```bash
scripts/release.sh 1.0.0
```

The script:
1. Refuses to start without the certificate, without the credentials, or
   with uncommitted changes.
2. Builds for arm64 and x86_64. The version is the argument; the build
   number is the number of commits.
3. Signs the app with the hardened runtime and a timestamp. B-Side has no
   entitlements: it is not sandboxed, and the page plays in WebKit's own
   processes.
4. Sends the app to the notary, waits (a few minutes), and staples the
   ticket to it.
5. Puts the app and a link to `/Applications` in a disk image, signs,
   notarises and staples the image, and asks Gatekeeper about it.
6. Leaves `dist/B-Side-<version>.dmg` and prints its SHA-256.

Then try the image as a user would: open it, drag B-Side to Applications,
start it. After that, tag and publish:

```bash
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 dist/B-Side-1.0.0.dmg --title "B-Side 1.0.0" --notes "<what is new>"
```

## Trying the script without Apple

```bash
scripts/release.sh 0.0.1 --adhoc
```

The same build and disk image, signed ad hoc and not notarised. It runs on
the Mac that built it and shows that the app works under the hardened
runtime.

## Before there is a certificate

B-Side is released as source: the README tells people to build it with
`./scripts/install.sh`. An app built on one's own Mac is not quarantined,
so Gatekeeper does not ask about it.

An `--adhoc` image can be put on GitHub as an unsigned download, but a
downloaded copy is stopped by Gatekeeper ("Apple could not verify…"). The
user has to allow it once in System Settings → Privacy & Security → Open
Anyway. Say so next to the download if you publish one.

## When the notary refuses

`notarytool` prints a submission ID. The reasons are in its log:

```bash
xcrun notarytool log <submission ID> --keychain-profile b-side-notary
```
