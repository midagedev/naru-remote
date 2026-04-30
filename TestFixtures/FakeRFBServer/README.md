# Fake RFB Server Fixture

This directory is reserved for the deterministic RFB/VNC fixture required by
`specs/001-naru-remote-mvp/plan.md`.

The first production implementation should use it to verify:

- protocol version negotiation
- DNS/TCP/RFB diagnostic stage behavior
- first-frame receipt
- `ClientCutText`/clipboard payload behavior
- paste command paths

`Fixtures/noauth-first-frame.hex` is a deterministic RFB 3.8 no-auth transcript
used by `RFBProtocolDecoderTests` and `FakeRFBServerIntegrationTests` to verify
the first handshake and framebuffer-update header parsing path.

Run the networked fake server from the repository root:

```bash
swift run FakeRFBServer --fixture TestFixtures/FakeRFBServer/Fixtures/noauth-first-frame.hex --port 5901
```

The executable serves the transcript to each TCP client and then closes the
connection. Clipboard and diagnostic behavior still use in-process fakes until
dedicated RFB messages are added to the fixture.
