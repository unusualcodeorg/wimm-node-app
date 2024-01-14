function seed(dbName, user, password) {
  db = db.getSiblingDB(dbName);
  db.createUser({
    user: user,
    pwd: password,
    roles: [{ role: 'readWrite', db: dbName }],
  });
}

seed('wimm-db', 'wimm-db-user', 'changeit');
seed('wimm-test-db', 'wimm-test-db-user', 'changeit');
