# untweetify

Delete each and every tweet you ever tweeted.

Also, do it with bash. Like real women do.

## Prerequisites

- an archive of your twitter data, in the form of a zip, delivered to you by twitter upon request at <https://twitter.com/settings/download_your_data>, unpacked. It's the `data/tweets.js` and `data/tweets-part*.js` files that are of interest to us.

- your own custom little twitter app created on the twitter developer dashboard, <https://developer.twitter.com/en/portal/dashboard/>
  - configure for oauth2 authorization, as a confidential client
  - set the callback URL to `http://localhost:1666/`
  - generate and copy the client ID and client secret

- bash, curl, nc and jq installed on your system

- export the following env variables

```sh
TW_CLIENT_ID=<your app client ID>
TW_CLIENT_SECRET=<your app client secret>
TW_ARCHIVE_PATH=<the path to where the data directory from the archive resides>
```

## Authenticate

Run

```sh
bash untweetify.sh auth
```

It should open a browser (or give you the URL to open manually) with a page where you must authorize the app to access your twitter account. Once the flow finishes without errors, it should inform you that

```txt
Yay. I am now authenticated and ready to nuke your tweets.
```

Never mind that your browser probably complained about the redirect page not working. We just didn't bother to send anything back to the browser once we got the authentication data.

## Prepare

Run

```sh
bash untweetify.sh prep
```

Once it finishes, you should get the following files in your working directory:

```txt
pending.txt
deleted.txt
```

The latter one being empty, and the former one containing all the IDs of the tweets you ever tweeted.

## Nuke

Run

```sh
bash untweetify.sh nuke
```

It will run a long while, as you are rate limited to deleting at most 50 tweets every 15 minutes. By default we do 45 tweets every 16 minutes as rate limiting never really works fine. Run this in a `screen` session or somesuch.

Once it's done, all the IDs of the tweets deleted are in `deleted.txt`, and there's also a file `failed.txt` that contains the IDs of the tweets that failed to be deleted.

If you preserve the `deleted.txt` file, the next run will only attempt to delete the tweets that are not present in this file.
