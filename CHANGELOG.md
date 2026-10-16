# Changelog

## 3.0.1

- **When you last used them:** the tooltip line now ends with how long ago your last order with a crafter was, like *last 12d ago*.
- **Quicker actions in the history window:** right-click an order to whisper the crafter (or customer) or look them up, and shift-click to link the item in chat.
- **/tc lookup on your target:** type `/tc lookup` with a player targeted to look them up. Lookups now include realm answers too.
- Fixed two bits of text that still said guild sharing was coming.

## 3.0.0

- **Realm sharing:** turn on "Share on my realm" in the options and Trust Crafter also asks other Trust Crafter users on your realm about a crafter, on a hidden channel that never shows in your chat. Answers come straight from whoever wrote them, by whisper.
- **Shown apart, always:** realm answers get their own line, *Realm (unverified): 4 orders from 2 people | 4/4 met or exceeded*, in tooltips, the history window and the crafting orders window. Guild members who answer still count as guild.
- **Checked like guild reviews:** realm orders are confirmed against the crafter's own log too.
- **Limits:** at most 20 orders per person per crafter (5 from the last week), counted by people; Trust Crafter answers at most 10 channel questions a minute and asks at most 20 an hour.
- **Ignore anyone:** right-click a player and choose "Ignore their Trust Crafter reviews", or `/tc ignore Name-Realm`.
- Realm answers are forgotten after 60 days; "Forget realm reviews" deletes them all. `/tc realm` shows whether the channel is connected.
- Separate from guild sharing and off by default.

## 2.0.0

- **Guild sharing:** turn on "Share with my guild" in the options and when you look a crafter up (the history window, `/tc lookup`, the personal order name box or a My Orders row), Trust Crafter asks your guild how their orders with that crafter went. Guild members' answers show beside your own, counted by people, not orders: *Guild: 7 orders from 3 people | 6/7 met or exceeded*. Works for crafters you've never used yourself.
- **Checked against the crafter's own log:** if the crafter runs Trust Crafter and is online, their Crafted for others log is asked about those orders. Each one is marked **confirmed** (same quality), **disputed** (a different quality) or **no record**. Your own orders get checked too, shown as "Crafter's log" in the history window.
- **What's shared:** outcome, quality asked for and received, time taken, order type, and tags and notes not marked private. Never the tip, never anything outside your guild. Answers come straight from whoever wrote them; nothing is passed on.
- Sharing is **off until you turn it on**. "Confirm orders I crafted" is on: it only ever tells a customer the quality you delivered for an order, never who it was for.
- Pauses during raid encounters and Mythic+ runs, when addon messages are locked, and catches up afterwards.
- "Forget guild reviews" in the options deletes everything your guild has shared with you.

## 1.4.0

- **Your customers on the crafting orders window:** when you browse public, guild or personal orders as a crafter, a tick marks customers you've crafted for before. Hover the order for how many times and how much they tipped, and open it to see the same beside their name.
- **Options page** in Esc > Options > AddOns (or `/tc options`): the tooltip line, online dots, minimap button, the crafting orders window and CraftScan lines, Export, Delete history and the debug log.
- **Online dots can be turned off.** With them off, Trust Crafter doesn't ask the game whether crafters are online at all.

## 1.3.0

- **Works with CraftScan:** if you use CraftScan to find crafting customers in chat, hovering a customer in its orders window or its new request banner now shows your Trust Crafter history with them: how many times you've crafted for them and how much they tipped, and how their orders went if they've crafted for you. Nothing changes if CraftScan isn't installed, and the line follows the existing tooltip setting.

## 1.2.0

- **Crafted for others:** a new tab in the history window logs every crafting order you fill for another player: the customer, the quality you delivered against what they asked for, your craft time from taking the order to filling it, and the tip. The top of the list adds up your orders, customers and tips, and it has the same search, outcome and profession filters.
- **Tooltip:** hovering a player you have crafted for says how many times and how much they tipped.
- **Export** now includes the orders you crafted for others, marked in a new `side` column.
- Orders from your own characters stay on the My orders tab, and NPC (patron) orders aren't logged.
- **Fixed:** a Lua error that repeated when mousing over players in dungeons and raids (Midnight's secret values).

## 1.1.0

- **Online dot beside every crafter:** green when they are online, red when the game says they are offline, grey when it can't tell. Shown in the history window, the order details, the personal order name box, the My Orders tooltip and `/tc lookup`.
- Uses the game's own whisper check plus your friends list, group and Battle.net friends. Nothing is sent to the crafter, and it pauses while chat is locked down in restricted content.
- Dots refresh every 30 seconds while the history window is open.

## 1.0.0

First version: your own crafting order ledger.

- **Every order you place is logged automatically:** crafter, quality asked for and received, when it was placed and filled, time taken, tip and order type.
- **Filled orders are picked up from your mail:** collecting the crafted item marks the order filled, with the crafter and quality read from the mail.
- **Orders filled by one of your own characters** (an alt crafting for your main) are marked filled the moment you fill them, with the exact time taken.
- **No rating your own work:** only the character who placed an order can rate it, and orders crafted by one of your own characters can't be rated.
- **Outcome worked out from the facts:** Met, Exceeded or Below, plus Not filled for orders nobody took (never counted against anyone).
- **Notes and tags** on your own orders: Fast, Friendly, Own mats, Would again, Slow. The facts can't be edited.
- **Tooltip line** on players you have used as a crafter.
- **On the crafting orders window:** your history beside the name when you send a personal order, and a tick on My Orders for crafters you have used before.
- **Right-click menu** on player names (chat, friends, guild, unit frames) shows your history with that crafter and opens it in the history window.
- **Export** your orders as CSV with `/tc export` or the Export button.
- **History window** (`/tc`) with sorting, search, and outcome and profession filters.
- **Minimap button** to open the history window; drag it to move, `/tc minimap` hides it.
- `/tc lookup`, `/tc tooltip`, `/tc wipe` and `/tc debug`.
