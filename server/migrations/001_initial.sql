CREATE TABLE users (
  id uuid PRIMARY KEY, email text NOT NULL UNIQUE, password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), CHECK (email = lower(email))
);
CREATE TABLE sessions (
  token_hash text PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions(user_id);
CREATE INDEX sessions_expiry_idx ON sessions(expires_at);
CREATE TABLE characters (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id),
  name text NOT NULL CHECK(char_length(name) BETWEEN 1 AND 80),
  background text NOT NULL CHECK(char_length(background)<=8000), style text NOT NULL CHECK(char_length(style)<=2000),
  revision integer NOT NULL CHECK(revision>0), context_version integer NOT NULL CHECK(context_version>0),
  created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, UNIQUE(owner_id,id)
);
CREATE TABLE entries (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), author text NOT NULL CHECK(author IN ('user','character')),
  character_id uuid, title text NOT NULL CHECK(char_length(title) BETWEEN 1 AND 200),
  body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 20000), revision integer NOT NULL CHECK(revision>0),
  context_version integer, created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, UNIQUE(owner_id,id),
  FOREIGN KEY(owner_id,character_id) REFERENCES characters(owner_id,id),
  CHECK((author='user' AND character_id IS NULL AND context_version IS NULL) OR
    (author='character' AND character_id IS NOT NULL AND context_version>0))
);
CREATE TABLE grants (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), character_id uuid NOT NULL, entry_id uuid NOT NULL,
  entry_revision integer NOT NULL CHECK(entry_revision>0), active boolean NOT NULL, revision integer NOT NULL CHECK(revision>0),
  created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, UNIQUE(owner_id,id), UNIQUE(owner_id,character_id,entry_id),
  FOREIGN KEY(owner_id,character_id) REFERENCES characters(owner_id,id), FOREIGN KEY(owner_id,entry_id) REFERENCES entries(owner_id,id)
);
CREATE TABLE conversations (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), character_id uuid NOT NULL, entry_id uuid,
  created_at timestamptz NOT NULL, UNIQUE(owner_id,id), UNIQUE(owner_id,character_id,id),
  FOREIGN KEY(owner_id,character_id) REFERENCES characters(owner_id,id), FOREIGN KEY(owner_id,entry_id) REFERENCES entries(owner_id,id)
);
CREATE TABLE jobs (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), character_id uuid NOT NULL,
  conversation_id uuid, user_message_id uuid, kind text NOT NULL CHECK(kind IN ('reply','diary')),
  status text NOT NULL CHECK(status IN ('pending','running','succeeded','failed','cancelled')),
  context_version integer NOT NULL CHECK(context_version>0), attempt integer NOT NULL CHECK(attempt>=0),
  lease_until timestamptz, run_token uuid, result_id uuid, error_code text, sources jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL, UNIQUE(owner_id,id),
  FOREIGN KEY(owner_id,character_id) REFERENCES characters(owner_id,id),
  FOREIGN KEY(owner_id,character_id,conversation_id) REFERENCES conversations(owner_id,character_id,id),
  CHECK((kind='diary' AND conversation_id IS NULL AND user_message_id IS NULL) OR (kind='reply' AND conversation_id IS NOT NULL AND user_message_id IS NOT NULL)),
  CHECK((status='running')=(lease_until IS NOT NULL AND run_token IS NOT NULL))
);
CREATE UNIQUE INDEX one_active_reply ON jobs(conversation_id) WHERE kind='reply' AND status IN ('pending','running');
CREATE UNIQUE INDEX one_active_diary ON jobs(character_id) WHERE kind='diary' AND status IN ('pending','running');
CREATE INDEX job_queue_idx ON jobs(status,created_at);
CREATE TABLE messages (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), character_id uuid NOT NULL, conversation_id uuid NOT NULL,
  role text NOT NULL CHECK(role IN ('user','assistant')), body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 20000),
  sequence integer NOT NULL CHECK(sequence>0), context_version integer NOT NULL CHECK(context_version>0), job_id uuid,
  created_at timestamptz NOT NULL, UNIQUE(owner_id,id), UNIQUE(conversation_id,sequence), UNIQUE(job_id),
  FOREIGN KEY(owner_id,character_id,conversation_id) REFERENCES conversations(owner_id,character_id,id),
  FOREIGN KEY(owner_id,job_id) REFERENCES jobs(owner_id,id)
);
ALTER TABLE jobs ADD FOREIGN KEY(owner_id,user_message_id) REFERENCES messages(owner_id,id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE memories (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES users(id), character_id uuid NOT NULL,
  body text NOT NULL CHECK(char_length(body) BETWEEN 1 AND 4000), sources jsonb NOT NULL CHECK(jsonb_array_length(sources) BETWEEN 1 AND 10),
  active boolean NOT NULL, revision integer NOT NULL CHECK(revision>0), created_at timestamptz NOT NULL, updated_at timestamptz NOT NULL,
  UNIQUE(owner_id,id), FOREIGN KEY(owner_id,character_id) REFERENCES characters(owner_id,id)
);
CREATE TABLE receipts (
  id uuid NOT NULL, owner_id uuid NOT NULL REFERENCES users(id), operation text NOT NULL, fingerprint text NOT NULL,
  resource_kind text NOT NULL, resource_id uuid NOT NULL, created_at timestamptz NOT NULL, PRIMARY KEY(owner_id,id)
);
CREATE FUNCTION reject_history_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Historical output is immutable' USING ERRCODE='23514'; END;
$$;
CREATE TRIGGER immutable_messages BEFORE UPDATE ON messages FOR EACH ROW EXECUTE FUNCTION reject_history_update();
CREATE TRIGGER immutable_character_entries BEFORE UPDATE ON entries FOR EACH ROW WHEN (OLD.author='character') EXECUTE FUNCTION reject_history_update();
CREATE INDEX characters_page ON characters(owner_id,created_at DESC,id DESC);
CREATE INDEX entries_page ON entries(owner_id,created_at DESC,id DESC);
CREATE INDEX grants_page ON grants(owner_id,character_id,created_at DESC,id DESC);
CREATE INDEX conversations_page ON conversations(owner_id,character_id,created_at DESC,id DESC);
CREATE INDEX messages_page ON messages(owner_id,conversation_id,created_at DESC,id DESC);
CREATE INDEX memories_page ON memories(owner_id,character_id,created_at DESC,id DESC);
CREATE INDEX jobs_page ON jobs(owner_id,created_at DESC,id DESC);
