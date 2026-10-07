// Fictional accounts for the local emulator only. Never uses a live project.
const project = 'demo-hemo-local';
const password = 'LocalTest123!';
const auth = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:';
const store = `http://127.0.0.1:8089/v1/projects/${project}/databases/(default)/documents`;
const timestamp = new Date().toISOString();
const encode = value => {
  if (value === null) return {nullValue: null};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number') return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  if (typeof value === 'string') return {stringValue: value};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([key, data]) => [key, encode(data)]))}};
};
async function account(email) {
  const body = JSON.stringify({email, password, returnSecureToken: true});
  let response = await fetch(`${auth}signUp?key=demo-local-only`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body});
  let result = await response.json();
  if (result.error?.message === 'EMAIL_EXISTS') {
    response = await fetch(`${auth}signInWithPassword?key=demo-local-only`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body});
    result = await response.json();
  }
  if (!response.ok) throw new Error(JSON.stringify(result.error));
  return result.localId;
}
async function document(path, data) {
  const fields = encode(data).mapValue.fields;
  fields.createdAt = {timestampValue: timestamp};
  const response = await fetch(`${store}/${path}`, {method: 'PATCH', headers: {'Content-Type': 'application/json', Authorization: 'Bearer owner'}, body: JSON.stringify({fields})});
  if (!response.ok) throw new Error(await response.text());
}
const fixtures = [
  ['admin', 'Local Admin', 'admin'],
  ['doctor', 'Local Doctor', 'doctor'],
  ['patient', 'New Patient', 'patient'],
  ['newpatient', 'Unassigned Patient', 'patient'],
  ['assigned', 'Assigned Patient', 'patient'],
  ['pending', 'Pending Doctor', 'pending_doctor'],
];
const ids = {};
for (const [key] of fixtures) ids[key] = await account(`${key}@hemo.test`);
for (const [key, name, role] of fixtures) {
  await document(`users/${ids[key]}`, {
    name, role, email: `${key}@hemo.test`, accountActive: true,
    isApproved: role === 'doctor' || role === 'admin',
    status: role === 'pending_doctor' ? 'pending_approval' : 'approved',
    doctorId: key === 'assigned' ? ids.doctor : null,
    age: 24, gender: 'Male', phoneNumber: '9876543210',
    consentVersion: '2026-10-02-v1', researchConsent: false,
    onboardingCompleted: true, diagnosisStatus: 'no',
    screeningAnswers: {age: 24, sex: 'male', easy_bruising: 'yes', family_history_bleeding_disorder: 'no'},
    screeningResult: {predictionLabel: 'Low risk', predictionConfidence: 0.7},
    registrationNumber: 'LOCAL-TEST-001', specialization: 'Physiotherapy',
    hospital: 'Local Test Clinic', qualification: 'BPT',
    patientId: `SHP-${ids[key].toUpperCase()}`,
  });
}
console.log('Local emulator accounts ready. Password: LocalTest123!');
for (const [key, name] of fixtures) console.log(`${name}: ${key}@hemo.test`);
console.log('patient@hemo.test is unassigned; assigned@hemo.test belongs to doctor@hemo.test.');
