# ADR 0001: Chunk Supabase sessions in SecureStore

## Status

Accepted — August 25, 2026

## Context

Supabase persists a serialized session containing sensitive access and refresh tokens. Expo SecureStore is the required native secure-storage boundary, but the maximum size of one secure item differs by platform and can be smaller than a serialized session.

## Decision

The mobile app writes only SecureStore entries. It splits each serialized Supabase session into small chunks and commits a SecureStore metadata record after all chunks are written. The adapter clears incomplete or corrupt sessions instead of returning partial credentials. It removes reachable chunks and metadata during sign-out.

No session token, encryption key, or session ciphertext is stored in AsyncStorage, SQLite, the TanStack Query cache, logs, screenshots, or source control.

## Consequences

- Session restoration survives normal app restart and remains inside the platform secure store.
- A corrupted session safely becomes signed out and requires a new authentication flow.
- The adapter has focused tests for large values, corruption, and deletion.

