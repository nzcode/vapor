import Async

/// Internal struct containing migrations for a single database.
/// note: This struct is important for maintaining database connection type info.
internal struct DatabaseMigrationConfig<Database: Fluent.Database>: MigrationRunnable where Database.Connection: QueryExecutor {
    /// The database identifier for these migrations.
    internal let database: DatabaseIdentifier<Database>

    /// Internal storage.
    internal var migrations: [MigrationContainer<Database>]

    /// Create a new migration config helper.
    internal init(database: DatabaseIdentifier<Database>) {
        self.database = database
        self.migrations = []
    }

    /// See MigrationRunnable.migrate
    internal func migrate(using databases: Databases, on worker: Worker) -> Future<Void> {
        let promise = Promise(Void.self)

        if let database = databases.storage[database.uid] as? Database {
            database.makeConnection(on: worker).then { conn in
                self.prepareForMigration(on: conn).chain(to: promise)
            }.catch(promise.fail)
        } else {
            promise.fail("no database \(database.uid) was found for migrations")
        }

        return promise.future
    }

    /// Prepares the connection for migrations by ensuring
    /// the migration log model is ready for use.
    internal func prepareForMigration(on conn: Database.Connection) -> Future<Void> {
        return MigrationLog<Database>.prepareMetadata(on: conn).flatMap { _ in
            return MigrationLog<Database>.latestBatch(on: conn).flatMap { lastBatch in
                return self.migrateBatch(on: conn, batch: lastBatch + 1)
            }
        }
    }

    /// Migrates this configs migrations under the current batch.
    /// Migrations that have already been prepared will be skipped.
    internal func migrateBatch(on conn: Database.Connection, batch: Int) -> Future<Void> {
        return migrations.map { migration in
            return { migration.prepareIfNeeded(batch: batch, on: conn) }
        }.syncFlatten()
    }

    /// Adds a migration to the config.
    internal mutating func add<M: Migration> (
        migration: M.Type
    ) where M.Database == Database {
        let container = MigrationContainer(migration)
        migrations.append(container)
    }
}

