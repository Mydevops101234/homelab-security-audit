# Network Segmentation: Before / After

Placeholders: `<LAN_IP>` = the host's LAN-facing IPv4 address.
`<host-public-ipv6>` represents any globally-routable IPv6 address a
residential ISP might assign directly to the router/host.

## Before

```mermaid
flowchart TB
    subgraph internet["Public Internet"]
        attacker(("Any host,\nincl. IPv6-only"))
    end

    subgraph host["Docker Host"]
        dns["DNS filter\n(LAN_IP only — OK)"]
        dash["Monitoring dashboard\n0.0.0.0 + [::]"]
        metrics["Metrics collector\n0.0.0.0 + [::]\nno auth"]
        exporter["System exporter\n0.0.0.0 + [::]\nno auth"]
        ci["CI server\n0.0.0.0 + [::]"]
        mgmt["Container mgmt UI\n0.0.0.0 + [::]"]
        webhook["Webhook receiver\n0.0.0.0\n(intentional — HMAC verified)"]
        game["Game server\ngame port 0.0.0.0 (intentional)\n+ RCON 0.0.0.0 + [::] (NOT intentional)"]
    end

    attacker -. "IPv4: blocked by router NAT" .-> dash
    attacker == "IPv6: NOT blocked — direct reachability" ==> dash
    attacker == "IPv6: NOT blocked" ==> metrics
    attacker == "IPv6: NOT blocked" ==> exporter
    attacker == "IPv6: NOT blocked" ==> ci
    attacker == "IPv6: NOT blocked" ==> mgmt
    attacker == "IPv6: NOT blocked" ==> game

    style dash fill:#7a1f1f
    style metrics fill:#7a1f1f
    style exporter fill:#7a1f1f
    style ci fill:#7a1f1f
    style mgmt fill:#7a1f1f
    style game fill:#7a1f1f
```

## After

```mermaid
flowchart TB
    subgraph internet["Public Internet"]
        client(("Any host"))
        webhook_sender["Third-party webhook sender\n(legitimate caller)"]
    end

    subgraph lan["LAN only (<LAN_IP>)"]
        lanclient(("LAN device"))
    end

    subgraph host["Docker Host"]
        dns["DNS filter"]
        dash["Monitoring dashboard"]
        webhook["Webhook receiver\n(HMAC-verified per request)"]
        game["Game server\ngame port only"]

        subgraph loopback["127.0.0.1 only"]
            metrics["Metrics collector"]
            exporter["System exporter"]
            cadvisor["Container metrics collector"]
        end

        subgraph internal_net["Internal Docker network\n(no host port at all)"]
            rcon["RCON"]
        end
    end

    client -. "blocked" .-> dash
    client -. "blocked" .-> metrics
    client -. "blocked" .-> game
    webhook_sender ==> webhook
    webhook -- "internal network,\nby service name" --> rcon
    lanclient --> dns
    lanclient --> dash

    style metrics fill:#1f5c2e
    style exporter fill:#1f5c2e
    style cadvisor fill:#1f5c2e
    style rcon fill:#1f5c2e
    style dns fill:#1f5c2e
    style dash fill:#2a4a6b
```

## Key structural change, not just narrower rules

The RCON fix (finding F5) isn't "restrict who can reach the port" — it's
"the port never touches the host network namespace in the first place."
Two services that need to talk to each other share a private Docker
network and resolve each other by container hostname; nothing about that
communication path requires or benefits from a host-published port at
all. That's a stronger guarantee than a firewall rule, because there's no
rule to misconfigure or accidentally remove later — the exposure is
structurally impossible, not just currently denied.
