# Blog posts

* [My agent setup by Chad Arimura](https://chad.cm/posts/2026-8-11-my-agent-setup)
* [Building an (almost) fully self-hosted, sandboxed, agentic software factory by Jake Saunders](https://blog.jakesaunders.dev/building-an-almost-fully-self-hosted-sandboxed-agentic-software-factory/)

# HN comments

pavo-etc 6 hours ago | next [-]

I've had a lot of success running Pi on my server in headless mode and wrapping it in an XMPP client.
This means I can talk to it wherever I can access
XMPP (everywhere). It also mean agents can talk to each other when they need to. They've got a shared wiki they interact with and github issues as their todo list.
I am running several named pi instances in parallel in their own user account on NixOS, so they can install whatever they want in ephemeral shells and I never need to worry about their env. The agents can spin up new enabled XMPP agents if I request it, though for now I've only needed a few since I'm not doing too much in parallel.
My Pi is very vanilla, only my own XMPP wrapper and pi-subagents extension for anonymous subagents.
Using it primarily with Deepseek v4 Flash for chipping away at coding tasks or server maintainence while I'm AFK or in transit.
NixOS is the key to all of this, since agents can interact see the whole server config, make changes and run compile-time checks before actually deploying. It also means that even if they do mess up I can always revert.