English | [中文](DESIGN.zh.md)

# Interface

The current visual source is the 2026-10-26 editorial draft.

The draft was a single HTML file. The product is the Flutter app. Implement this visual system there. Do not start a separate website.

## Tone

The Proclaim Wall announcement wall. Black, white, and gray. Hairlines. Small radii on otherwise square corners. One sans family for titles. Separate them with size and weight, not with color. The accent is the current foreground: white in dark, near-black in light. Red is only for destructive actions.

With no stored choice, theme follows the system brightness and language follows the system locale. Match only Chinese and English. Anything else uses Chinese. After a choice, `proclan.theme` is `dark` or `light`, and `proclan.locale` is `zh` or `en`. Settings has no control that returns to the system.

## Color

Dark:

| Use | Value |
| --- | --- |
| Background | `#000000` |
| Card | `#1a1a1a` |
| Input, thumbnail well | `#030303` |
| Body | `#ffffff` |
| Secondary body | `#e9ecf2` |
| Support | `#8a919c` |
| Meta | `#7d848e` |
| Line | `#27272a` |
| Weak line | `#232326` |
| Hover line | `#3f3f46` |
| Accent / text on accent | `#ffffff` / `#000000` |
| Danger text | `#ff6b74` |
| Danger button | `#dc2626` |
| Success | `#4ade80` |

Light uses `#f4f4f5` for the background, white for cards, `#09090b` for body text, and `#e4e4e7` for lines. The accent becomes `#09090b` with white text on it. Danger text is `#b91c1c`.

Radii: 4 for buttons and inputs, 8 for cards and avatars. Motion is `cubic-bezier(.2, 0, 0, 1)`.

The type stack is PingFang SC, then Inter, DM Sans, and the system Chinese fonts. The draft preferred Inter for Latin, and the app does not bundle that family, so the interface names PingFang SC.

Column widths: feed 960, article and settings 820. Horizontal padding is 4% of the screen width, clamped between 16 and 40.

## Login

On a wide screen, two columns, and the left one is slightly wider. The left pane is the seaside photograph with two darkening layers and the headline "Your feed. Your rules." The right card is vertically centered and starts at the title. The login line is "Sign in to read your own daily." The link is "Create account". Register links back with "Back to sign in".

Both modes ask for a username and a password. Register shows the note "This is your login name. It must be unique, and you can change it later." A narrow screen stacks the photograph above the form. An error is prefixed with a "!" badge. The other locale uses its own strings for the same layout.

## Feed

The masthead is the date: a large day, the month and weekday, and the count for this edition. On the right are unread, refresh, and the user avatar, which opens settings. The avatar is the first character of the username. A Latin letter is uppercased. It matches the avatar on Me. Until the username has loaded, the masthead mark is blank.

The unread control opens "Unread only". With nothing unread it is disabled and reads "All read". While that filter is on, the control steps aside and the filter row is how you leave it.

Categories are a row of outlined chips. The selected chip fills with the accent. A card is an outlined rectangle: category, reading time, title, a two-line summary, source, and time. When there is an image, the thumbnail sits on the right. The article hero stays above the summary. Days are groups. Today is open. Earlier days start collapsed.

## Article

The top bar sticks. Back is on the left. Category and time are in the center. A reading progress line runs along the bottom edge. The body sits in an outlined card: image, title, summary, body, tags, source. Mark unread is an outlined button. Delete is a danger outline. The confirm button in the dialog is red with white text. The hero image is clipped to an 8px radius. The body renders Markdown.

## Settings

The feed pushes into Me. The profile card is a square avatar, the name, and "Edit". Three stats sit under it: bot count, unread count, cache window. "Reading" opens preferences, account, and bots. "More" is privacy and sign out. Back on a subpage returns to Me. Back on Me returns to the feed. The back tooltip is "Back".

Preferences are appearance, language, unread only, cache, and auto sync. Dark and light apply immediately.

Account is a username field and its note: this is the login name, it must be unique, and it can be changed later. Save is a solid button aligned to the right. Saving keeps the session. The new name is the next login name.

Password is a separate page: current password, then new password. Success signs the user out and returns to login. The bot token stays as it is.

The bot page lists names. A name opens its detail. Basics show the first time it appeared and its role, then every push the server still holds. Opening a card and going back returns only to that bot. Deleting the name removes it from the list. The cards stay. The next push with the same name adds the name again. Under the token there is one button, which copies an MCP install prompt. The prompt names no client. The wording follows the UI language. The copy includes the current bot token and this app's server origin. The prompt says to read the live `submit_cards` inputSchema each time and to fill that schema, and not to copy fields into the prompt.

Privacy says the data stays on the person's own server and on this device. After the feed scrolls past one screen, a control at the lower right returns to the top.

## Do not change

The launcher icon is a black field with a silver letter P. Category wire values, on-device read state, and the split between the login session and the bot token do not follow this draft.
