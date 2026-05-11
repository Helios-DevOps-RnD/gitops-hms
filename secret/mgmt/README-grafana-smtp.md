# Grafana SMTP Secret — kubeseal template

Gmail dipakai sebagai SMTP relay untuk Grafana alerting.
Secret ini hanya berlaku untuk **mgmt cluster**.

## 1. Buat Gmail App Password

1. Buka [myaccount.google.com/security](https://myaccount.google.com/security)
2. Pastikan **2-Step Verification** aktif
3. Cari **"App passwords"** → Create → pilih "Mail" + "Other"
4. Simpan 16-digit password yang muncul → masukkan ke step 2

## 2. Seal dengan kubeseal

```bash
kubectl create secret generic grafana-smtp-secret \
  --from-literal=user=devopshin@gmail.com \
  --from-literal=password=<APP_PASSWORD_16_DIGIT> \
  --namespace=monitoring \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  --format yaml \
  > grafana-smtp-sealed-secret.yaml
```

## 3. Commit & push

```bash
git add infrastructure/monitoring/grafana/grafana-smtp-sealed-secret.yaml
git commit -m "feat: add Grafana SMTP SealedSecret (Gmail)"
git push
```

## Catatan

- App Password JANGAN di-commit ke repo
- Simpan App Password di Azure Key Vault sebagai backup
- SealedSecret hanya bisa didecrypt oleh mgmt cluster
- Gmail limit: 500 email/hari — cukup untuk internal alerting
