CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS resources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    resource_type VARCHAR(60) NOT NULL DEFAULT 'laboratorio',
    capacity INT NOT NULL DEFAULT 1,
    available BOOLEAN NOT NULL DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reservations (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id),
    resource_id INT NOT NULL REFERENCES resources(id),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS event_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(20) NOT NULL,
    source VARCHAR(80) NOT NULL,
    message TEXT NOT NULL,
    context JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO users (email, password_hash, full_name)
VALUES ('admin@lab.edu', 'scrypt:1$8$labsecret$placeholder', 'Administrador Lab')
ON CONFLICT (email) DO NOTHING;

INSERT INTO resources (name, resource_type, capacity, description)
SELECT * FROM (VALUES
    ('Lab Virtualización A', 'laboratorio', 20, 'Equipos Incus y red OVN'),
    ('Sala Servidores B', 'sala', 8, 'Cluster académico'),
    ('Aula Cloud C', 'aula', 30, 'Prácticas OpenTofu/Ansible')
) AS v(name, resource_type, capacity, description)
WHERE NOT EXISTS (SELECT 1 FROM resources LIMIT 1);
