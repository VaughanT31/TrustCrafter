# TrustCrafter

A World of Warcraft addon that remembers who crafted your orders, what quality you asked for and what you actually got.

**New here?** The [wiki](wiki/Home.md) explains every feature step by step (also on the [website](https://ctrlshiftzed.com/wiki/trustcrafter/)). Questions it doesn't answer: ask on [Discord](https://discord.gg/wz7fw6jM9Z).

Crafting orders are full of crafters you know nothing about. TrustCrafter keeps a private ledger of every order you place, so the next time you see a crafter you can tell at a glance whether they have done good work for you before.

- **Game:** Retail, Midnight (12.x)
- **Interface:** `120105`

## What it does

**Logs every order automatically.** No typing needed. For each crafting order you place it records:

- who crafted it
- the quality you asked for and the quality you got
- when it was placed, when it was filled and how long that took
- the tip you paid and whether it was a public, guild or personal order

**Works out the outcome from the facts.** Each order is marked *Met*, *Exceeded* or *Below* by comparing the quality you asked for with the quality you got. Orders that were never filled are kept but never held against anyone.

**Lets you add your own note and tags** (*Fast*, *Friendly*, *Own mats*, *Would again*, *Slow*). Your words sit next to the facts, never on top of them:

- You can only add a note to an order you actually placed.
- The facts can't be edited.
- There is no "failed" button. An order that met the quality you asked for always shows as met.
- How long an order took is shown as a number, never as a score.

**Shows it where you need it.** Hover a player you have used as a crafter:

```
TrustCrafter: crafted 4x for you  |  4/4 met or exceeded  |  avg 38 min
```

You also see it:

- **On the crafting orders window:** type a crafter's name for a personal order and your history with them shows beside the name. In My Orders, a tick marks crafters you have used before (yellow if any order came in below what you asked for), and hovering the order adds your history to its tooltip.
- **In the right-click menu** on a player's name in chat, the friends list, your guild or a unit frame. Click it to open your history with that crafter.

**Is the crafter online?** A dot beside each crafter: green when they are online, red when the game says they are offline, grey when it can't tell (for example a player on another realm it can't reach). It uses the game's own whisper check plus your friends list and group, and sends nothing to the crafter.

**History window** (`/tc` or the minimap button): every order on this realm, sortable by date, crafter, item, outcome, time taken or tip, with search and outcome and profession filters.

**Crafted for others:** the second tab of the history window logs every crafting order you fill for another player: who it was for, the quality you delivered against what they asked for, how long you took from taking the order to filling it, and the tip. The top of the list adds up how many orders, for how many customers and how much in tips. Hover a player you have crafted for and the tooltip says so too ("you crafted 3x for them"). Orders from your own characters stay on the My orders tab, and NPC (patron) orders aren't logged. This is also your side of each order for guild sharing, coming next.

**Your customers when you craft:** browsing public, guild or personal orders as a crafter, a tick marks customers you've crafted for before. Hover the order for how many times and how much they tipped; open it and the same shows beside their name.

**Options:** Esc > Options > AddOns > TrustCrafter, or `/tc options`. Turn the tooltip line, online dots, minimap button, crafting orders window and CraftScan lines on or off, export, or delete your history.

**Guild sharing (2.0):** turn on *Share with my guild* in the options. Look a crafter up (history window, `/tc lookup`, the personal order name box or a My Orders row) and Trust Crafter asks your guild how their orders with them went, even for a crafter you've never used: *Guild: 7 orders from 3 people | 6/7 met or exceeded | 5 confirmed*.

- Answers come straight from whoever wrote them, by whisper. The server fills in who sent an addon message, so nobody can answer as someone else, and nothing is passed on.
- If the crafter runs Trust Crafter and is online, their own Crafted for others log is asked about those orders: **confirmed** (same quality), **disputed** (a different quality) or **no record**. Your own orders are checked the same way.
- Shared: outcome, quality asked for and received, time taken, order type, and tags and notes not marked private. Never tips, never outside your guild.
- Off until you turn it on. *Confirm orders I crafted* is on: it only tells a customer the quality you delivered for their order, never who an order was for.

**Works with CraftScan:** if you also use [CraftScan](https://www.curseforge.com/wow/addons/craftscan) to find customers in chat, hovering a customer in its orders window or its new request banner shows your history with them, so you know who you've crafted for before and how they tipped. Nothing changes if CraftScan isn't installed.

**Export:** `/tc export` (or Export in the history window) gives you every order as CSV to paste into a spreadsheet, the ones you placed and the ones you crafted for others (the `side` column says which).

Personal orders count the same as public and guild ones. The order type is kept with each order, so you can always see which it was.

Everything is kept per realm, because public crafting orders only reach crafters on your own realm.

## How orders get logged

- **Placing an order** at a crafting orders NPC logs it straight away.
- **Collecting your mail** marks it filled (or expired): the crafted item arrives by mail, and TrustCrafter reads the crafter and quality from it. Mail doesn't say exactly when it was sent, so the time taken is worked out from it and shown with a "~".
- **Opening My Orders** at the NPC also updates everything the game lists there.
- **Crafting for your own alts:** an order one of your characters fills is marked filled the moment you fill it.

Orders you placed before installing TrustCrafter are added too, for as long as the game still lists them. Their placing time is unknown, so no time taken is shown for those.

**Only the character who placed an order can rate it**, and orders crafted by one of your own characters can't be rated at all, so nobody can review their own work.

## Commands

| Command | What it does |
|---|---|
| `/tc` | Open or close your order history (or click the minimap button) |
| `/tc options` | Open the options |
| `/tc minimap` | Hide or show the minimap button |
| `/tc lookup Name` | What you know about a crafter (no name: your target) |
| `/tc export` | Copy your orders as CSV for a spreadsheet |
| `/tc tooltip` | Turn the tooltip line on or off |
| `/tc wipe` | Delete your history on this realm (asks first) |
| `/tc realm` | Whether realm sharing is connected |
| `/tc ignore Name-Realm` | Ignore a player's realm reviews (`/tc unignore` to undo) |
| `/tc desk` | The Crafter Desk: requests from chat and its settings (or Shift-click the minimap button) |
| `/tc busy` | Mark yourself busy (or not) for Find a Crafter and Crafter Desk replies |
| `/tc note text` | A short note customers see when they find you (empty clears it) |
| `/tc debug` | Log crafting order events to chat, for bug reports |
| `/tc help` | List commands |

## Realm sharing (3.0)

Turn on **Share on my realm** in the options and TrustCrafter also asks other TrustCrafter users on your realm about a crafter. It uses a hidden channel: joined a minute after login as a temporary channel, removed from every chat tab, and used only for addon messages. Questions go on the channel; answers come back by whisper from whoever wrote them, so nothing is relayed.

- Realm answers are their own tier, **Realm (unverified)**, never mixed into your own or your guild's numbers. Guild members who answer still count as guild.
- At most 20 orders per person per crafter, and 5 from the last week; counted by people, not orders.
- Right-click a reviewer, or `/tc ignore Name-Realm`, to ignore their reviews.
- Realm answers are forgotten after 60 days. "Forget realm reviews" in the options deletes them all.
- The channel takes one of your 10 chat channel slots. If it's locked or you're removed from it, a backup channel is used. `/tc realm` shows the status.
- Separate from guild sharing, and off by default.

## Find a Crafter (3.1)

Turn on **Find a Crafter** in the options (or click the **Find a Crafter** button on a personal order, which asks first). The button asks the hidden realm channel and your guild who knows the recipe. Crafters with Find a Crafter on whisper back which of their characters know it, so every answer comes from the crafter themselves.

- Results are sorted by trust: your own good orders first, then good guild reviews, then good realm reviews, then crafters who are online and not busy. Your own characters that know the recipe are listed last.
- **Use** puts the name in the order's recipient box. **Whisper** opens a whisper. Hover a row for the full history; the first few crafters' guild and realm reviews are asked for straight away.
- As a crafter, open each profession once per character so its learned recipes are known. "Include my other characters" lists your alts too; "Let customers find me" can be turned off to search without being listed.
- Mark yourself busy with `/tc busy`, and add a short note with `/tc note Free with your mats`.
- Searches: at most one per recipe every 30 seconds and 20 an hour. Answers: at most 10 a minute, spread over a couple of seconds. Ignored players' answers are dropped.
- Uses the same hidden channel as realm sharing, so it takes one chat channel slot. Off by default.

## Crafter Desk (4.0)

Turn on **Watch chat for crafting requests** (options, or `/tc desk` > Settings). When someone in Trade, Services or a whisper asks for something one of your characters can craft, an alert shows who, what, which of your characters makes it, the quality you can reach with and without concentration, the material cost (with Auction Coach), your history with them and how often it was asked today.

- A message counts when it has a request word (LF, WTB, need, recraft, anyone craft...) and no ignore word (WTS, LFW, LF work, selling...). Both lists are editable, and the test box shows what any chat line would do.
- Matches: item links to anything your characters craft, keywords you gave an item, this expansion's item names, related words made from those names ("generosity chest" for Allied Chestplate of Generosity, shown in grey in the Keywords column), and asking for your profession by name or short form (LF bs, LF jc).
- **Characters** (left of the window): every character on the realm. Tick the ones to watch for, click one for its **Items** (watchlist: each recipe on or off, the quality it makes, your keywords, and *Only max quality*) and **Messages** (its own replies, one per line with {name} {item} {character} {profession} {quality} {commission} {mats}, and its own commission).
- When several of your characters know a recipe, the one that makes it at max quality answers first, then the one you're on, then the most skilled.
- **Greet** whispers one reply, built from varied pieces in your tone (Friendly, Short, Formal) and answering what they asked: quality, whose mats, your commission (when they ask about price, or always), and which character to send the order to. Hover to read it first, right-click for another wording.
- Never automatic: one click per whisper, one greeting per request, none to the same person for the same thing within 10 minutes, at most 5 a minute.
- **Requests** lists the last week with today's numbers. A greeted request becomes *ordered* when you fill an order for that customer within a day.
- **Mute item** stops alerts for an item; right-click a request to ignore a player. Right-click a name in chat for **Reply as a crafter**.
- **Desk button:** opens the desk and lights up with a count when a request comes in. Hover for who's asking and what you'd say; left-click greets, middle-click whispers, right-click dismisses, Shift-click opens the desk. Pick its place in the options (below the minimap, top, right edge, above the action bars, or off) or Shift-drag it anywhere. Key bindings for greet, whisper, dismiss and open are under Key Bindings > AddOns.
- Drag the alert bar where you want it and click **Pin** to keep it on screen between requests.
- Alert cards show the proposed greeting and can be turned off in the options if you'd rather use just the button.
- In a watchlist, the quality in brackets is what you reach with concentration; hover an item for the details.
- Open each profession once on each character so the desk knows its recipes and quality. Off by default.

## Installation

Install from CurseForge or Wago, or copy the `TrustCrafter` folder into `World of Warcraft/_retail_/Interface/AddOns/` and `/reload`.

## License

MIT, see [LICENSE](LICENSE).

Guild sharing uses these libraries, included under their own licenses: [AceComm-3.0 and CallbackHandler-1.0](https://www.wowace.com/projects/ace3) (Ace3, BSD), [ChatThrottleLib](https://www.wowace.com/projects/chatthrottlelib) (public domain), [LibStub](https://www.wowace.com/projects/libstub) (public domain), [LibSerialize](https://github.com/rossnichols/LibSerialize) (MIT) and [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) (zlib).
