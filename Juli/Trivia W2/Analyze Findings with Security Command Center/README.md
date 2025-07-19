#  Analyze Findings with Security Command Center


#### ⚠️ Disclaimer :
**Script dan panduan ini disediakan untuk tujuan edukasi agar Anda dapat memahami proses lab dengan lebih baik. Sebelum menggunakannya, disarankan untuk meninjau setiap langkah guna memperoleh pemahaman yang lebih mendalam. Pastikan untuk mematuhi ketentuan layanan Qwiklabs, karena tujuan utamanya adalah mendukung pengalaman belajar Anda.**

### Run the following Commands in CloudShell 

```
curl -LO raw.githubusercontent.com/andregregs/gcaf/refs/heads/main/Juli/Trivia%20W2/Analyze%20Findings%20with%20Security%20Command%20Center/GSP1164.sh
sudo chmod +x GSP1164.sh

./GSP1164.sh
```

### Paste in the following schema:
```
[   
  {
    "mode": "NULLABLE",
    "name": "resource",
    "type": "JSON"
  },   
  {
    "mode": "NULLABLE",
    "name": "finding",
    "type": "JSON"
  }
]
```