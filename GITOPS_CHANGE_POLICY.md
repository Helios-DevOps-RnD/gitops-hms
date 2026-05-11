# GitOps Change Policy

## 1. Purpose

Dokumen ini mendefinisikan kebijakan perubahan untuk repository GitOps `gitops-hms` yang menggunakan pendekatan:

- Single branch (`main`)
- Folder-based environment separation
- Kustomize `base` + `overlays`
- Continuous deployment menggunakan Argo CD

Tujuan utama:

- Menjamin keamanan perubahan, terutama untuk production
- Menjaga konsistensi antar environment
- Mencegah configuration drift
- Menyediakan audit trail yang jelas

## 2. Core Principles

1. Git adalah satu-satunya source of truth
2. Semua perubahan wajib melalui Pull Request (PR)
3. Tidak ada direct push ke branch `main`
4. Tidak ada perubahan manual di cluster workload
5. Argo CD adalah single deployment mechanism
6. Perubahan wajib mengikuti boundary folder dan environment yang jelas

## 3. Repository Structure Convention

Repository ini mengikuti pola berikut:

```text
apps/
  └── <service>/
        ├── base/
        └── overlays/
              ├── staging/
              └── production/

infrastructure/
  └── <component>/
        ├── base/
        └── overlays/
              ├── staging/
              └── production/
```

### Classification

| Path | Scope | Risk Level |
| --- | --- | --- |
| `**/overlays/staging/` | Staging only | Medium |
| `**/overlays/production/` | Production only | High |
| `**/base/` | Shared across environments | Critical |
| `argocd/apps/staging/` | Staging deployment definitions | Medium |
| `argocd/apps/production/` | Production deployment definitions | High |
| `argocd/infrastructure/*-staging.yaml` | Staging infra deployment | Medium |
| `argocd/infrastructure/*-production.yaml` | Production infra deployment | High |
| `argol bootstrap operations | Critical |
cd/projects/` | Shared Argo CD governance | Critical |
| `bootstrap/` | Manua
## 4. Change Classification Rules

Setiap PR harus secara eksplisit menyatakan area perubahan:

- Staging Change: hanya boleh menyentuh path staging
- Production Change: hanya boleh menyentuh path production
- Base Change: perubahan di `base/` yang berdampak ke semua environment
- Argo CD Governance Change: perubahan di `argocd/` yang memengaruhi deployment behavior
- Bootstrap Change: perubahan pada script manual bootstrap, diperlakukan sebagai critical change

Aturan wajib:

- 1 PR hanya untuk 1 scope perubahan utama
- PR yang mencampur staging dan production akan ditolak
- PR yang mencampur overlay environment dengan `base/` harus diperlakukan sebagai `base change`
- Perubahan di `base/`, `argocd/projects/`, atau `bootstrap/` dianggap production-level atau lebih tinggi

## 5. Pull Request Policy

### 5.1 General Rules

- Semua perubahan wajib melalui PR
- Tidak boleh ada direct push ke `main`
- PR harus fokus, kecil, dan dapat diaudit
- PR wajib menjelaskan alasan perubahan dan impact area
- PR wajib menyebut path yang terdampak

### 5.2 Scope Rules

- PR staging hanya boleh menyentuh:
  - `apps/**/overlays/staging/**`
  - `infrastructure/**/overlays/staging/**`
  - `argocd/apps/staging/**`
  - `argocd/infrastructure/*-staging.yaml`
- PR production hanya boleh menyentuh:
  - `apps/**/overlays/production/**`
  - `infrastructure/**/overlays/production/**`
  - `argocd/apps/production/**`
  - `argocd/infrastructure/*-production.yaml`
- PR base hanya boleh digunakan untuk perubahan bersama dan harus di-review lebih ketat

### 5.3 Mandatory PR Template

```md
## Environment
- [ ] staging
- [ ] production
- [ ] shared/base

## Affected Path
<path>

## Change Type
- [ ] image update
- [ ] configuration
- [ ] secret rotation
- [ ] infrastructure
- [ ] argo cd governance

## Risk Level
- [ ] medium
- [ ] high
- [ ] critical

## Validation
- [ ] Rendered with kustomize
- [ ] YAML validation passed
- [ ] Policy validation passed
- [ ] Tested in lower environment

## Checklist
- [ ] No image tag `latest`
- [ ] Resource requests/limits remain defined
- [ ] No privileged container introduced
- [ ] Promotion flow respected
- [ ] Rollback path is clear
```

## 6. Approval Policy

Approval berbasis path dan risk level.

### 6.1 Rules

| Scope | Minimum Approval | Requirement |
| --- | --- | --- |
| staging | 1 | Service owner atau developer terkait |
| production | 2 | DevOps mandatory + service owner/tech lead |
| base | 2 | DevOps mandatory + architect/tech lead |
| `argocd/projects/` | 2 | DevOps mandatory + architect |
| `bootstrap/` | 2 | DevOps mandatory + architect |

### 6.2 CODEOWNERS Example

```text
* @devops-team

/apps/**/overlays/staging/* @backend-team @frontend-team
/apps/**/overlays/production/* @devops-team @tech-leads

/infrastructure/**/overlays/staging/* @devops-team
/infrastructure/**/overlays/production/* @devops-team @tech-leads

/apps/**/base/* @devops-team @architects
/infrastructure/**/base/* @devops-team @architects

/argocd/apps/staging/* @devops-team
/argocd/apps/production/* @devops-team @tech-leads
/argocd/projects/* @devops-team @architects

/bootstrap/* @devops-team @architects
```

## 7. CI/CD Validation Policy

Semua PR wajib lolos pipeline validasi sebelum merge.

### 7.1 Manifest Validation

- `kustomize build` untuk path yang berubah
- `kubeconform` atau `kubeval`
- Validasi schema untuk resource Argo CD bila path `argocd/` berubah

### 7.2 Security Policy

Gunakan `Kyverno`, `OPA Gatekeeper`, atau policy checker setara.

Minimal policy:

- Tidak boleh menggunakan image tag `latest`
- Wajib memiliki resource requests dan limits
- Tidak boleh privileged container
- Tidak boleh host networking tanpa approval eksplisit
- Secret tidak boleh dalam bentuk plain-text manifest

### 7.3 Path-Based Enforcement

CI harus mendeteksi path yang berubah:

- Jika menyentuh `overlays/production`:
  - enforce strict validation
  - require production approval policy
- Jika menyentuh `base/`:
  - treat sebagai critical change
  - jalankan validasi untuk semua overlay yang bergantung pada base tersebut
- Jika menyentuh `argocd/projects/` atau `bootstrap/`:
  - treat sebagai critical governance change

## 8. Promotion Policy

### 8.1 Mandatory Flow

```text
staging -> production
```

### 8.2 Rules

- Tidak boleh langsung mengubah production tanpa bukti verifikasi di staging
- Perubahan image, config, dan secret harus diuji di staging terlebih dahulu
- Perubahan `base/` harus divalidasi minimal pada staging sebelum boleh dipromosikan ke production

### 8.3 Promotion Method

#### Option A - Manual Promotion

- Copy perubahan yang sudah tervalidasi dari staging ke production melalui PR baru

#### Option B - Image Tag Promotion (Recommended)

Contoh:

```text
staging    -> registry.hms.internal/hms/<app>:<git-short-sha-or-rc>
production -> registry.hms.internal/hms/<app>:<approved-release-tag>
```

Jika menggunakan promotion by tag:

- Tag production harus immutable
- Tag production hanya boleh berasal dari artifact yang sudah lolos staging
- `patch-image.yaml` menjadi titik kontrol utama promosi

## 9. Argo CD Policy

### 9.1 Access Control

| Role | Access |
| --- | --- |
| Developer | Read-only production, update via PR only |
| QA | Observe staging results, tidak deploy manual ke production |
| DevOps | Full governance access |

### 9.2 Sync Policy

| Environment | Sync |
| --- | --- |
| staging | Auto |
| production | Auto atau manual sesuai risk policy organisasi |

Jika production tetap auto-sync, maka approval dan CI validation wajib lebih ketat sebelum merge.

### 9.3 Self-Healing

- Harus aktif untuk environment yang dikelola Argo CD
- Digunakan untuk mencegah configuration drift
- Drift harus diperbaiki melalui Git, bukan lewat perubahan manual di cluster

## 10. Guardrails (Non-Negotiable)

### Forbidden

- Direct push ke `main`
- Manual `kubectl apply`, `kubectl edit`, atau patch resource workload di cluster
- Menggunakan image tag `latest`
- PR yang mencampur staging dan production
- Mengubah production tanpa approval DevOps
- Commit secret mentah ke repository

## 11. Risk Mitigation

### Risk: Accidental Production Change

Mitigasi:

- CODEOWNERS
- Path-based CI validation
- PR scope enforcement

### Risk: Base Change Impacting All Environments

Mitigasi:

- Treat `base/` sebagai critical change
- Higher approval requirement
- Render dan validate seluruh overlay terkait

### Risk: Skipping Staging

Mitigasi:

- Enforce promotion policy
- Wajib evidence pengujian staging pada PR production

### Risk: Manual Drift Outside Git

Mitigasi:

- Argo CD self-heal
- Batasi akses cluster
- Audit perubahan melalui PR dan commit history

## 12. Summary

Model single-branch GitOps memindahkan kompleksitas dari branching ke governance.

Agar aman dan scalable di repository `gitops-hms`:

- Gunakan folder sebagai boundary environment
- Terapkan approval berbasis path
- Wajibkan CI validation dan policy enforcement
- Terapkan promotion flow `staging -> production`
- Gunakan Argo CD sebagai satu-satunya deployment mechanism

Tanpa governance yang kuat, model ini berisiko tinggi terhadap stabilitas production.
