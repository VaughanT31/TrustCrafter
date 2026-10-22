# Changelog

## 4.1.0

- **A bigger Crafter Desk:** drag the bottom right corner to make the window bigger. The columns get wider and the lists show more rows, and it remembers the size. Shift-drag still scales the whole window.
- **Ordered, then Delivered:** a request now says *Ordered* when you take an order from that customer and *Delivered* once you fill it, and today's numbers count both.
- **Quiet requests leave the list:** a request goes once nothing has happened for 10 minutes (no new ask, greeting or whisper from them), and 10 minutes after it's delivered. One you've taken an order for stays until it's delivered.
- **Item names load:** requests and alert cards no longer show *item 240949* while the game is still loading the item; they ask the game for it and fill in the name as soon as it arrives, using their link until then.
- **Seconds on new alerts:** an alert card counts up in seconds for its first minute (*12 sec*), then in minutes.

## 4.0.0

- **Crafter Desk:** turn it on and Trust Crafter watches Trade, Services and your whispers (General too, if you want) for people asking for something one of your characters can craft. An item link matches exactly, this expansion's item names match too, and so does asking for your profession (*LF blacksmith*).
- **More in every alert:** who's asking and what for, which of your characters can make it, the quality you can reach (with and without concentration), roughly what the materials cost when Auction Coach is installed, your history with them (*you crafted 3x for them, 150g in tips, last 12d ago*), and how often it's been asked for today.
- **Replies that don't sound like a bot:** **Greet** whispers a reply built from varied pieces in your tone (Friendly, Short or Formal). It answers what they asked: the quality you can make, whose mats, your commission when they ask about price, and which character to send the order to. Hover Greet to read it first, right-click for another wording. Never sent without a click, never the same text twice in a row, one greeting per request and at most 5 a minute.
- **Requests page:** `/tc desk` (or Shift-click the minimap button) lists every request from the last week with today's numbers: asked, greeted, and ordered (when you fill an order for someone you greeted).
- **Every crafter, your way:** the desk window lists all your characters on the realm. Tick the ones to watch for; one that hasn't opened its professions yet says so. Right-click a character to delete it from the watch list (it comes back if it opens a profession again). Drag the corner of the window to make it bigger (it never grows past your screen). The window opens in the middle of the screen and stays wherever you move it. Click a character to see its **watchlist**: every recipe it knows with the quality it makes, ticked on or off, with your own keywords per item (*bracers*, *plate wrist*). **Only max quality** keeps a character to the items it makes at max quality with the best materials and concentration.
- **The right character answers:** when more than one of your characters knows a recipe, the one that makes it at max quality is picked first, then the one you're playing, then the most skilled. The reply names that character.
- **Write your own replies:** each character can have its own replies on the **Messages** page, one per line, picked at random and never the same twice in a row. Placeholders: {name} {item} {character} {profession} {quality} {commission} {mats}, and a placeholder with nothing to fill is left out cleanly. Each character can have its own commission too, and *Copy to all characters* shares them. Leave it empty for the built-in replies.
- **Related words from item names:** people rarely type the whole name, so each item also matches the short ways they ask for it: *Allied Chestplate of Generosity* matches "generosity chest", "generosity chestplate" and "chestplate of generosity", *Sunfire Silk Bolt* matches "sunfire silk" and "silk bolt". A word two of your items share is left out so it can't pick the wrong one. They show in grey beside your own keywords, and can be turned off in the options.
- **A desk button where you want it:** a small button opens the desk and lights up with a count when a request comes in. Hover it for who's asking and what you'd say; left-click greets them, middle-click opens a whisper, right-click dismisses, Shift-click opens the desk. Put it below the minimap, at the top, on the right edge or above the action bars, Shift-drag it anywhere, or turn it off in the options. The same actions can be bound to keys (Key Bindings > AddOns > TrustCrafter).
- **Skill reagents count:** the quality a character can reach now also tries the optional and finishing reagents that add skill (Artisan's Consortium Gold Star and the like) on top of the best materials, with and without concentration. A watchlist shows it after a **+**, and the tooltip names the reagents, what they're made from (5 of the one before) and roughly what they cost with Auction Coach. Reagents for multicraft, resourcefulness or ingenuity don't change the rank, so they're left out.
- **Cities and sanctuaries only:** the desk listens only in a city, inn or sanctuary and never in combat, so nothing runs while you're out questing or fighting.
- **The right finishing reagent:** when a character already makes max quality with the best materials, the watchlist and alert say which finishing reagent to add: Resourceful first (materials back), then Multicraft, with Ingenious last since it only refunds concentration. When max needs concentration, Ingenious moves up to second. The better version is picked when the recipe takes it.
- **No rank:** items without ranks say *no rank* instead of a rank icon, and replies don't mention quality for them.
- **Their own item back:** when they link the item, the reply uses their exact link, with its item level and quality, so a recraft shows the very piece. A long link that won't fit falls back to the plain one.
- **Fewer wrong matches:** words inside a link to something you don't make no longer match other items, and related words are always two words or more.
- **Requests only while they matter:** the list shows how long ago each request came in, and drops it after 10 minutes unless they whispered you back or ordered. Today's numbers still count them.
- **Whispers with each customer:** hover a request to see the whispers you sent and got from that person since, with times, kept for a week.
- **A character's own commission is always said:** the commission on a character's Messages page now goes in every reply for that character; the general one still waits for a price question unless *Always* is ticked.
- **Pick the alert sound:** whisper, group invite, ready check, raid warning, Auction House, map ping, friend online or alarm clock. Picking one in the options plays it.
- **Pin the alert bar:** drag it where you want it and click **Pin**, and it stays there between requests (also in the options). Its position is remembered either way.
- **Alert cards show what you'd say:** each card has the proposed greeting under the request. Turn the cards off to keep the screen clear and use the button and the sound instead.
- **Quality in brackets is with concentration:** hover an item on a watchlist to see the quality with the best materials and with concentration, and how much concentration it takes.
- **Settings you can check:** pick which chats to watch, your tone and commission, edit the request and ignore words, and paste any chat line into the test box to see whether it would alert and why. Mute an item straight from its alert.
- **Reply as a crafter:** right-click a player's name in chat to reply to their last message, even if the desk didn't pick it up.
- Open each profession once on each character so the desk knows your recipes and the quality you can make. The Crafter Desk is off until you turn it on.
- For addon authors: `TrustCrafterAPI.GetCustomerSummary(name)` and `TrustCrafterAPI.GetCrafterSummary(name)` return a one-line summary from your own logs. Patron Planner shows it on personal and guild order cards.

## 3.1.0

- **Find a Crafter:** a new button beside the name box on personal orders. It asks other Trust Crafter users on your realm, and your guild, who knows the recipe, then lists them with your history, your guild's reviews and the realm's. Crafters you've had good orders from come first, then good reviews, then crafters who are online and not busy. **Use** puts their name on the order, **Whisper** opens a whisper, and hovering shows their full history.
- **Be found as a crafter:** with Find a Crafter on, your characters are listed when someone searches for a recipe they know. Open each profession once so Trust Crafter knows its recipes. Your other characters on the realm are listed as alts (you can turn that off), and you can turn off being listed at all.
- **Busy and a note:** mark yourself busy (`/tc busy` or the options) and add a short note customers see, like *Free with your mats* (`/tc note`).
- Answers come straight from the crafter by whisper, at most 10 a minute, and ignored players are left out. Uses the same hidden realm channel as realm sharing, and is off until you turn it on (the button asks first).

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
