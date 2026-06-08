# Maintaining the Manual

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This page is the maintenance guide for the HSS operator manual. It states how to keep the manual accurate as the code evolves: when a code change obliges a documentation change, which document each kind of change touches, how versions and identifiers are managed across revisions, and the checks to run before a documentation change merges.

It is written for the person making a change to the `udr` source — a developer or maintainer — not for an operator. Every other document in this manual is operator-facing; this one is the exception, because the obligation it describes falls on whoever changes the code.

This page follows the project documentation standard, the `documenting-hss` house standard at [`.claude/skills/documenting-hss/`](../../.claude/skills/documenting-hss/), as does every document it governs.

## 1. The core rule — docs move with code

A change to observable behavior `shall` update the affected manual document in the same change set (the same commit or pull request) that changes the code.

Observable behavior is anything an operator can see or set from outside the running system, as defined by the standard's verifiability rule ([documentation-style §8](../../.claude/skills/documenting-hss/documentation-style.md)): a configuration key or its default, an interface request or response, a status or result code, a log line, an [OpenTelemetry](glossary.md) span or metric, a bind address or port, a release name, or a start command.

> [!IMPORTANT]
> A change that alters observable behavior without updating the matching document leaves the manual describing a system that no longer exists. Misinterpretation caused by a stale document is a deployment defect, not a documentation nicety. The documentation change and the code change are one unit of work.

A change that touches only internal implementation — a refactor with no externally visible difference — need not change the manual, because the manual documents *what* the operator configures and observes, not *how* the code is built. When in doubt, ask whether the change alters anything an operator could observe through a Verify step; if it does, the manual changes too.

## 2. Change-impact map

The table below maps a kind of code change to the document(s) that `shall` be updated in the same change set. The "Also check" column lists documents that frequently — but not always — need a matching edit; review them and update where the change reaches them.

> [!NOTE]
> This map reflects the manual's actual layout: the per-subsystem files under [`configuration/`](configuration/README.md), [`interfaces/`](interfaces/README.md), [`operations/`](operations/README.md), and [`troubleshooting/`](troubleshooting/README.md), plus the top-level [`overview.md`](overview.md), [`install.md`](install.md), [`quickstart.md`](quickstart.md), [`security.md`](security.md), [`compatibility.md`](compatibility.md), [`glossary.md`](glossary.md), and the diagram set under [`diagrams/`](diagrams/README.md).

| Kind of code change | `shall` update | Also check |
| --- | --- | --- |
| Change a parameter, an `application:get_env` default, or a `config/sys.config` value for an OTP application | The matching `configuration/<subsystem>.md` parameter table — see the [configuration index](configuration/README.md) for the application-to-file mapping (e.g. `udr_diameter` → [diameter.md](configuration/diameter.md), `udr_db` → [data-store.md](configuration/data-store.md)) | [quickstart.md](quickstart.md) if it sets the key; the parameter's **Since** field |
| Add, change, or remove an SBI route or response | [interfaces/sbi.md](interfaces/sbi.md) (§4 operations table, §5 operation detail, §7 status codes) | [quickstart.md](quickstart.md); [diagrams/README.md](diagrams/README.md) if a sequence diagram shows it; [troubleshooting/sbi.md](troubleshooting/sbi.md) |
| Add, change, or remove a provisioning field or status code | [interfaces/provisioning.md](interfaces/provisioning.md) (§4/§5/§7) | [quickstart.md](quickstart.md); [operations/provisioning.md](operations/provisioning.md); [troubleshooting/provisioning.md](troubleshooting/provisioning.md) |
| Change an S6a command, an AVP, or a Diameter result code | [interfaces/s6a.md](interfaces/s6a.md) (§5 operation detail, §7 status / result codes) | Any [troubleshooting/s6a.md](troubleshooting/s6a.md) entry citing that code; [diagrams/README.md](diagrams/README.md) sequence diagrams 3–4 |
| Add a new error path, status code, or operator-visible error string | The matching `troubleshooting/<subsystem>.md` (a new `TS-*` entry) and the status-code table of the matching interface reference | The interface reference's §7 |
| Change the release name, the build commands, or the start/stop commands | [install.md](install.md) and [operations/deploy.md](operations/deploy.md) / [operations/lifecycle.md](operations/lifecycle.md) | [operations/README.md](operations/README.md) conventions; [quickstart.md](quickstart.md) |
| Change clustering or Erlang distribution behavior | [configuration/cluster.md](configuration/cluster.md), [operations/cluster.md](operations/cluster.md), [troubleshooting/cluster.md](troubleshooting/cluster.md) | [diagrams/README.md](diagrams/README.md) diagram 2; [security.md](security.md) `SEC-004` |
| Change a default bind address or port, or add a new listener | [security.md](security.md) (§2 exposures) and [overview.md](overview.md) (§5 deployment topology) | The matching `configuration/<subsystem>.md`; the listener-default lines in the [operations](operations/README.md) and [troubleshooting](troubleshooting/README.md) READMEs; [diagrams/README.md](diagrams/README.md) |
| Change observability: a span name, a metric, an exporter, or an OTLP default | [configuration/observability.md](configuration/observability.md), [operations/observability.md](operations/observability.md), [troubleshooting/observability.md](troubleshooting/observability.md) | [quickstart.md](quickstart.md) §7 |
| Change the data backend, its options, or backup/restore behavior | [configuration/data-store.md](configuration/data-store.md), [operations/backend.md](operations/backend.md), [operations/backup-restore.md](operations/backup-restore.md), [troubleshooting/data-store.md](troubleshooting/data-store.md) | The persistence-model note in [operations/README.md](operations/README.md) |
| Change how secret material (Ki / OPc) is handled at rest, in transit, or in backups | [security.md](security.md) (`SEC-002`/`SEC-005`) and [operations/secrets.md](operations/secrets.md) | [interfaces/sbi.md](interfaces/sbi.md) §5.1; [interfaces/provisioning.md](interfaces/provisioning.md) |
| Change the upgrade procedure or a version-to-version migration step | [operations/upgrade.md](operations/upgrade.md) | [compatibility.md](compatibility.md) |
| Change the supported toolchain, OTP version, or a verified peer | [compatibility.md](compatibility.md) (§1 toolchain, §3 interoperability matrix) | [install.md](install.md) §1 prerequisites |
| Add a new term or abbreviation used anywhere in the manual | [glossary.md](glossary.md) | The document that introduced the term |
| Add or change an architecture relationship between applications | [overview.md](overview.md) | [diagrams/README.md](diagrams/README.md) |

> [!TIP]
> The map is keyed by what changed in the code, not by where you expect to write. Start from the change, follow the row, and update every document in the "`shall` update" cell before opening the change for review.

## 3. Versioning and identifiers

### 3.1 The header convention

Every document under `docs/manual/` carries a two-field header directly below its title:

```markdown
**Applies to:** udr <version> · **Revised:** <YYYY-MM-DD>
```

- **Applies to** records the software version the document describes. It `shall` name the release version the document was last verified against.
- **Revised** records the date the document last changed. It `shall` be updated to the date of the change whenever the document's content changes.

A change that edits a document's content `shall` update that document's **Revised** date. A change that alters the behavior a document describes `should` also review the document's **Applies to** version (see §4).

### 3.2 Stable identifiers

The manual assigns a stable identifier to each individually referenced item:

| Scheme | Identifies | Defined in |
| --- | --- | --- |
| The parameter key itself (e.g. `origin_host`, `backend`) | A configuration parameter | the `configuration/` references |
| `IF-S6A-*`, `IF-SBI-*`, `IF-PROV-*` | An interface operation | the `interfaces/` references |
| `RUN-<TASK>-NNN` (e.g. `RUN-PROVISION-001`) | An operational procedure | the `operations/` runbooks |
| `TS-<AREA>-NNN` (e.g. `TS-S6A-003`) | A troubleshooting entry | the `troubleshooting/` guides |
| `SEC-NNN` (e.g. `SEC-001`) | A security exposure | [security.md](security.md) |

These identifiers `shall not` be renumbered when a document is revised:

- A new item `shall` receive a new, previously unused identifier. It `shall not` reuse the number of a removed item.
- A removed item `shall` be marked withdrawn in place, rather than deleted and its number reassigned. A withdrawn entry retains its identifier and states that it is withdrawn and why.

> [!IMPORTANT]
> Identifiers are renumber-stable because other documents and external references point at them. [troubleshooting/s6a.md](troubleshooting/s6a.md) cites a result code documented under an `IF-S6A-*` operation; [security.md](security.md) cites `RUN-SECRETS-001` and `RUN-BACKUP-001`; the [diagram set](diagrams/README.md) cites interface sections by their `IF-*` identifier. Renumbering one identifier silently breaks every reference that points at it, inside the manual and outside it. Adding and withdrawing — never renumbering — keeps those references valid.

## 4. Per-release upkeep

On cutting a release, the following review `should` be performed as part of the release change set:

1. The **Applies to** stamp of each manual document `should` be reviewed. A document whose described behavior is unchanged from the previous release `may` keep its existing version; a document whose behavior the release changed `shall` have been updated under §1 already, and its **Applies to** `should` name the new release.
2. [compatibility.md](compatibility.md) `should` record any newly verified peer interoperability (§3 matrix) and any toolchain or OTP-version change (§1) introduced by the release.
3. The version string itself `should` be reconciled. The manual currently states `udr 0.1.0` throughout — in the **Applies to** header of every document, and in the release-name and version conventions of [operations/README.md](operations/README.md) and the runbooks. A release that changes the version set in the `relx` section of `rebar.config` `shall` update those stamps to match; a stale stamp claims a verification that did not happen.

> [!NOTE]
> The release version is the single value set in `rebar.config`'s `relx` block. [operations/README.md](operations/README.md) and [install.md](install.md) name it; the per-document **Applies to** headers repeat it. Treat `rebar.config` as the source and the manual stamps as the followers.

## 5. Change management — pre-merge checks

Every documentation change `should` be reviewed against the standard's review checklist (the [`SKILL.md` review checklist](../../.claude/skills/documenting-hss/SKILL.md)) before it merges. That review covers the substantive defects: vague quantities, a misused verbal form, a parameter without a default, a procedure without an observable Verify, an undefined abbreviation, mixed normative and informative text.

In addition, the maintainer `should` run the mechanical checks below from the repository root. They are the same kinds of check used to validate this manual, and each one `should` produce no output (an empty result is a pass):

```sh
# 1. No "must" / "has to" / "required to" / "mandatory" in normative text — use shall/should/may/can.
grep -rniE '\b(must|has to|have to|required to|mandatory)\b' docs/manual && echo 'FAIL: forbidden verbal form' || echo 'OK: verbal forms'

# 2. American spelling — flag the common British form used in this domain.
grep -rni 'signalling' docs/manual && echo 'FAIL: British spelling' || echo 'OK: spelling'

# 3. Broken relative .md links — every linked file resolves on disk.
for f in $(find docs/manual -name '*.md'); do d=$(dirname "$f"); \
  grep -oE '\]\([^)#]+\.md' "$f" | sed -E 's/^\]\(//' | while read -r l; do \
    [ -f "$d/$l" ] || echo "BROKEN: $f -> $l"; done; done

# 4. Every abbreviation used is defined in the glossary. List the bold terms the
#    glossary defines, then eyeball any new abbreviation a change introduced
#    against that list. (Run, then confirm new terms appear.)
grep -oE '^\| \*\*[^*]+\*\*' docs/manual/glossary.md | sed -E 's/^\| \*\*//; s/\*\*$//'
```

> [!NOTE]
> Check 4 lists the defined terms rather than asserting a pass automatically, because deciding whether a token is an abbreviation that needs a glossary entry is a judgment a script cannot make reliably. After adding a term to the manual, confirm it appears in this list; if it does not, add it to [glossary.md](glossary.md) per the change-impact map.

> [!TIP]
> Checks 1–3 are deterministic and `may` be wired into continuous integration so a forbidden verbal form, a British spelling, or a broken link fails the build before review.

## 6. Definition of done for a documentation change

A documentation change is done when all of the following hold:

- [ ] Every document named in the change-impact map (§2) for the code change is updated in the same change set.
- [ ] Each edited document's **Revised** date is updated, and its **Applies to** version is reviewed (§3.1).
- [ ] No existing identifier (`IF-*`, `RUN-*`, `TS-*`, `SEC-*`, or a parameter key) is renumbered; new items have new identifiers and removed items are marked withdrawn (§3.2).
- [ ] Every new or changed configuration parameter carries name, application, type, default, allowed values, unit, description, effect, and **Since** ([documentation-style §7](../../.claude/skills/documenting-hss/documentation-style.md)).
- [ ] Every new or changed procedure and configuration change ends with an observable **Verify** step ([documentation-style §8](../../.claude/skills/documenting-hss/documentation-style.md)).
- [ ] Normative and informative text are separated; asides use the correct admonition type; verbal forms are `shall` / `should` / `may` / `can` with no "must".
- [ ] Every abbreviation the change introduces is defined once in [glossary.md](glossary.md).
- [ ] The pre-merge checks (§5) pass: no forbidden verbal form, no British spelling, no broken relative link, and every new abbreviation is in the glossary.
- [ ] The change has been reviewed against the [`SKILL.md` review checklist](../../.claude/skills/documenting-hss/SKILL.md).

## 7. Related documents

- [`.claude/skills/documenting-hss/documentation-style.md`](../../.claude/skills/documenting-hss/documentation-style.md) — the documentation standard this guide enforces.
- [`.claude/skills/documenting-hss/SKILL.md`](../../.claude/skills/documenting-hss/SKILL.md) — the authoring and review checklists referenced in §5 and §6.
- [README.md](README.md) — the manual's table of contents and layout.
- [glossary.md](glossary.md) — the canonical terms every other document links to.
