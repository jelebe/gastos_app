// Crea (o reutiliza) el hogar de los dos usuarios y sube el diccionario de categorías.
// Uso:
//   HOUSEHOLD_UID_1=xxxx HOUSEHOLD_UID_2=yyyy node seed.js
//
// Requiere seed/serviceAccountKey.json (Firebase Console > Configuración del proyecto
// > Cuentas de servicio > Generar nueva clave privada). No se sube a git.

const admin = require('firebase-admin');
const categories = require('./categories.json');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

const uid1 = process.env.HOUSEHOLD_UID_1;
const uid2 = process.env.HOUSEHOLD_UID_2;
const householdName = process.env.HOUSEHOLD_NAME || 'Nuestro hogar';
const currency = process.env.HOUSEHOLD_CURRENCY || 'EUR';

if (!uid1 || !uid2) {
  console.error('Faltan HOUSEHOLD_UID_1 y/o HOUSEHOLD_UID_2.');
  process.exit(1);
}

const COMBINING_MARKS = new RegExp(
  '[' + String.fromCharCode(0x300) + '-' + String.fromCharCode(0x36f) + ']',
  'g'
);

function slugify(text) {
  return text
    .normalize('NFD')
    .replace(COMBINING_MARKS, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

async function findExistingHousehold() {
  const snapshot = await db
    .collection('households')
    .where('members', 'array-contains', uid1)
    .get();

  return snapshot.docs.find((doc) => (doc.data().members || []).includes(uid2));
}

async function main() {
  let householdRef;
  const existing = await findExistingHousehold();

  if (existing) {
    householdRef = existing.ref;
    console.log(`Hogar ya existente reutilizado: ${householdRef.id}`);
  } else {
    householdRef = await db.collection('households').add({
      name: householdName,
      members: [uid1, uid2],
      currency,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Hogar creado: ${householdRef.id}`);
  }

  const categoriesRef = householdRef.collection('categories');
  const batch = db.batch();

  for (const category of categories) {
    const id = slugify(`${category.grupo}-${category.nombre}`);
    batch.set(categoriesRef.doc(id), category, { merge: true });
  }

  await batch.commit();
  console.log(`${categories.length} categorías sincronizadas en households/${householdRef.id}/categories`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
