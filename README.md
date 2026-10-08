# TrustCrafter

A World of Warcraft addon that remembers who crafted your orders, what quality you asked for and what you actually got.

Crafting orders are full of crafters you know nothing about. TrustCrafter keeps a private ledger of every order you place, so the next time you see a crafter you can tell at a glance whether they have done good work for you before.

- **Game:** Retail, Midnight (12.x)
- **Interface:** `120100`

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

**Export:** `/tc export` (or Export in the history window) gives you every order as CSV to paste into a spreadsheet.

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
| `/tc minimap` | Hide or show the minimap button |
| `/tc lookup Name` | What you know about a crafter |
| `/tc export` | Copy your orders as CSV for a spreadsheet |
| `/tc tooltip` | Turn the tooltip line on or off |
| `/tc wipe` | Delete your history on this realm (asks first) |
| `/tc debug` | Log crafting order events to chat, for bug reports |
| `/tc help` | List commands |

## Coming next

- **Guild sharing:** see how your guild's orders with a crafter went, with orders confirmed by both the customer and the crafter.
- **Realm sharing:** ask other TrustCrafter users on your realm about a crafter, always labelled separately from what you and your guild know.

Sharing will be off by default, and notes marked private never leave your computer.

## Installation

Install from CurseForge or Wago, or copy the `TrustCrafter` folder into `World of Warcraft/_retail_/Interface/AddOns/` and `/reload`.

## License

MIT, see [LICENSE](LICENSE).
