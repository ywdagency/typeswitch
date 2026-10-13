# Publication review — 2026-10-12

This public repository begins with a reviewed snapshot of the current implementation. The private development history, internal task logs, local diagnostics, signing material, build outputs, and user-specific state are excluded.

Gitleaks 8.30.1 reported zero findings across all local refs of the development history and across the publication working files. Additional text checks found no private machine paths, personal author email, private-network references, or private-key blocks in the publication. These checks reduce exposure risk; they do not prove that every security defect is absent.

The copied source, tests, and scripts match the development snapshot. Dictionary word content is unchanged; resource comment headers now identify the applicable licenses. Public documentation was rewritten or curated, and full upstream license notices were added. Git author metadata uses GitHub's noreply address.

`swift test` passed all 121 tests from the independent publication checkout. Manual permission and real-app compatibility checks were not completed by this publication review; the experimental warning and the existing compatibility matrix remain in place. No signed/notarized binary is distributed by this publication.

## Russian inflection update review — 2026-10-12

The Russian inflection update includes pinned, hash-verified Hunspell bases and suffix rules with the existing upstream notice preserved. Local verification passed 130 Swift tests, 3 Python generator tests, and a release build. CI runs both test suites and the release build. The compatibility matrix remains unchanged because these checks do not establish real-editor compatibility.

Gitleaks 8.30.1 reported zero findings in the published `main` history and the 113 files prepared for this update. Additional checks found no private machine paths, private author contact address, private-network references, or private-key blocks in those files. The local development snapshot is outside `main` ancestry and is not included in the push. Git uses GitHub noreply author metadata. App bundles, local key material, build outputs, logs, environment files, and Python caches are excluded from version control. The GitHub repository is already public and private vulnerability reporting is enabled.
