const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000/api',
);
const kAdminEmail = String.fromEnvironment(
  'ADMIN_EMAIL',
  defaultValue: 'admin@gmail.com',
);
const kAdminPassword = String.fromEnvironment(
  'ADMIN_PASSWORD',
  defaultValue: 'admin!',
);