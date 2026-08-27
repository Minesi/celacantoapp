// One-off script: import tools from SIVS_PADROES xlsx into Firestore 'instrumentos'.
// Usage:
//   node import.js            -> dry run, only prints parsed rows, no Firestore writes
//   node import.js --commit   -> actually writes to Firestore
//
// Requires scripts/import_ferramentas/serviceAccountKey.json (Firebase service account key,
// downloaded from Firebase Console > Project Settings > Service Accounts for project ocrion-eda2a).
// That file must NOT be committed to git (it is gitignored).

const path = require('path');
const fs = require('fs');
const XLSX = require('xlsx');

const XLSX_PATH = path.join(__dirname, '..', '..', 'SIVS_PADROES_11.08.26.5.03.00.pm.xlsx');
const SHEET_NAME = 'SIVS';
const HEADER_ROW_INDEX = 1; // 0-based; row 2 in the spreadsheet holds the headers
const DOMINIO_EMPRESA = 'celacanto.com';
const VALIDADE_REGEX = /^(0[1-9]|1[0-2])\/\d{4}$/;

const COMMIT = process.argv.includes('--commit');

// Mirrors InstrumentoModel.validadeEhValida (lib/instrumento_model.dart)
function validadeEhValida(validadeStr) {
  const partes = (validadeStr || '').trim().split('/');
  if (partes.length !== 2) return false;
  const mes = parseInt(partes[0], 10);
  const ano = parseInt(partes[1], 10);
  if (Number.isNaN(mes) || Number.isNaN(ano) || mes < 1 || mes > 12) return false;
  const dataLimite = new Date(ano, mes, 0, 23, 59, 59); // last day of `mes` at 23:59:59
  return new Date() <= dataLimite;
}

function normalizeHeader(h) {
  return (h || '')
    .toString()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase();
}

function parseWorkbook() {
  const workbook = XLSX.readFile(XLSX_PATH);
  const sheet = workbook.Sheets[SHEET_NAME];
  if (!sheet) {
    throw new Error(`Sheet "${SHEET_NAME}" not found. Available: ${workbook.SheetNames.join(', ')}`);
  }

  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, range: HEADER_ROW_INDEX, defval: '' });
  const header = rows[0].map(normalizeHeader);
  const tagIdx = header.indexOf('tag');
  const tipoIdx = header.indexOf('descricao');
  const validadeIdx = header.indexOf('validade');

  if (tagIdx === -1 || tipoIdx === -1 || validadeIdx === -1) {
    throw new Error(`Could not find TAG/Descrição/Validade columns. Header row was: ${JSON.stringify(rows[0])}`);
  }

  const results = [];
  for (let i = 1; i < rows.length; i++) {
    const row = rows[i];
    const excelRowNumber = i + HEADER_ROW_INDEX + 1; // 1-based spreadsheet row number
    const tagRaw = (row[tagIdx] || '').toString().trim();
    if (!tagRaw) {
      continue; // blank tag rows are just spreadsheet padding, not real tools
    }

    const tipo = (row[tipoIdx] || '').toString().trim();
    const validadeRaw = (row[validadeIdx] || '').toString().trim();
    let validade = '';
    if (validadeRaw) {
      if (VALIDADE_REGEX.test(validadeRaw)) {
        validade = validadeRaw;
      } else {
        console.warn(`Row ${excelRowNumber} (tag ${tagRaw}): validade "${validadeRaw}" is not in MM/AAAA format, leaving blank.`);
      }
    }

    results.push({
      excelRowNumber,
      tag: tagRaw.toUpperCase(),
      tipo,
      validade,
      estaValido: validade ? validadeEhValida(validade) : false,
    });
  }
  return results;
}

async function writeToFirestore(rows) {
  const admin = require('firebase-admin');
  const keyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(keyPath)) {
    throw new Error(`Missing service account key at ${keyPath}. Download it from Firebase Console first.`);
  }
  admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  const db = admin.firestore();
  const collection = db.collection('instrumentos');

  let created = 0;
  let merged = 0;
  let untouched = 0;
  const BATCH_LIMIT = 500;

  for (let i = 0; i < rows.length; i += BATCH_LIMIT) {
    const chunk = rows.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();

    for (const row of chunk) {
      const docRef = collection.doc(row.tag);
      const snap = await docRef.get();

      if (!snap.exists) {
        batch.set(docRef, {
          tipo: row.tipo,
          tag: row.tag,
          numeroSerie: '',
          numeroCertificado: '',
          validade: row.validade,
          estaValido: row.estaValido ? 1 : 0,
          dominio_empresa: DOMINIO_EMPRESA,
        });
        created++;
        continue;
      }

      const existing = snap.data();
      const fill = {};
      if (!existing.tipo && row.tipo) fill.tipo = row.tipo;
      if (!existing.validade && row.validade) {
        fill.validade = row.validade;
        fill.estaValido = row.estaValido ? 1 : 0;
      }

      if (Object.keys(fill).length > 0) {
        batch.set(docRef, fill, { merge: true });
        merged++;
      } else {
        untouched++;
      }
    }

    await batch.commit();
  }

  console.log(`\nFirestore write summary: ${created} created, ${merged} merged, ${untouched} untouched (already fully filled).`);
}

async function main() {
  const rows = parseWorkbook();
  console.log(`Parsed ${rows.length} tools from the spreadsheet.\n`);
  console.table(rows.map(({ excelRowNumber, tag, tipo, validade, estaValido }) => ({ excelRowNumber, tag, tipo, validade, estaValido })));

  if (!COMMIT) {
    console.log('\nDry run only (no Firestore writes). Re-run with --commit to write.');
    return;
  }

  await writeToFirestore(rows);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
