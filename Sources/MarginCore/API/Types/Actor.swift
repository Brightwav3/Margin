/// Who performs a write (contract rule 0, `10-agent-native.md` §1.3). Every write method of every
/// service takes one; it ends up in the `ChangeSet` and, later, in the audit log.
///
/// Encoded as `{"kind": "user"}`, `{"kind": "system"}` or
/// `{"kind": "agent", "identity": …, "client": …, "session": …, "purpose": …}`.
///
/// Note: in files that import `MarginCore` this type shadows `Swift.Actor` (the concurrency
/// protocol, which code rarely names; `actor` declarations are unaffected).
public enum Actor: Sendable, Hashable {
    /// The person using the app.
    case user
    /// An agent working under an identity, through a paired client, in a session.
    case agent(AgentContext)
    /// The app itself (index maintenance, migrations, generated notes).
    case system

    /// Convenience for `.agent(AgentContext(…))`.
    public static func agent(identity: String, client: String, session: String, purpose: String? = nil) -> Actor {
        .agent(AgentContext(identity: identity, client: client, session: session, purpose: purpose))
    }

    /// Short stable text for logs and idempotency keys: `user`, `system`, `agent:<identity>/<session>`.
    public var label: String {
        switch self {
        case .user: "user"
        case .system: "system"
        case .agent(let a): "agent:\(a.identity)/\(a.session)"
        }
    }
}

/// The agent part of an `Actor`. AG-01 extends this (profile, scope); keep additions optional so
/// stored audit lines stay readable.
public struct AgentContext: Codable, Sendable, Hashable {
    /// Identity (role) the agent acts as, e.g. `study-helper`.
    public var identity: String
    /// The paired client that connected (`claude-code`, `cli`).
    public var client: String
    /// Session id issued by the app when the client took over the identity.
    public var session: String
    /// Why the agent works (shown to the user, kept in the audit).
    public var purpose: String?

    public init(identity: String, client: String, session: String, purpose: String? = nil) {
        self.identity = identity; self.client = client; self.session = session; self.purpose = purpose
    }
}

extension Actor: Codable {
    private enum CodingKeys: String, CodingKey { case kind, identity, client, session, purpose }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "user": self = .user
        case "system": self = .system
        case "agent":
            self = .agent(AgentContext(
                identity: try c.decode(String.self, forKey: .identity),
                client: try c.decode(String.self, forKey: .client),
                session: try c.decode(String.self, forKey: .session),
                purpose: try c.decodeIfPresent(String.self, forKey: .purpose)))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown actor kind '\(other)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user: try c.encode("user", forKey: .kind)
        case .system: try c.encode("system", forKey: .kind)
        case .agent(let a):
            try c.encode("agent", forKey: .kind)
            try c.encode(a.identity, forKey: .identity)
            try c.encode(a.client, forKey: .client)
            try c.encode(a.session, forKey: .session)
            try c.encodeIfPresent(a.purpose, forKey: .purpose)
        }
    }
}
