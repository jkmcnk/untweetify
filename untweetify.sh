#!/bin/bash

if [ -z "$TW_CLIENT_ID" -o -z "$TW_CLIENT_SECRET" ]; then
  echo "You need to set your app client ID and secret via env vars TW_CLIENT_ID and TW_CLIENT_SECRET"
  exit 1
fi

BASIC_AUTH=`echo -n "$TW_CLIENT_ID:$TW_CLIENT_SECRET"|base64 -w0`

if [ "$1" = "auth" ]; then
  touch code.txt
  chmod 0600 code.txt
  mkfifo response.pipe
  cat response.pipe | nc -l localhost 1666 1>code.txt 2>&1 &
  NCPID=$!
  CHALLENGE=`dd if=/dev/random bs=16 count=1|base64|sed -re 's/[\/+=]/x/g'`
  URL="https://twitter.com/i/oauth2/authorize?response_type=code&client_id=$TW_CLIENT_ID&redirect_uri=http://localhost:1666/&scope=tweet.read%20users.read%20tweet.write%20offline.access&state=state&code_challenge=$CHALLENGE&code_challenge_method=plain"
  echo Visit the following URL in the browser and authorize your untweet app:
  echo $URL
  xdg-open "$URL" 1>/dev/null 2>&1

  while true; do
    if ! grep -E '^GET ' code.txt 1>/dev/null 2>&1; then 
      sleep 1
    else
      CODE=`cat code.txt | grep '^GET ' | sed -re 's/.*&code=([^ &]+).*/\1/'`
      break
    fi
  done

  if [ -z "$CODE" ]; then
    echo "Failed to get authorization code."
    cat <<EOF >response.pipe
HTTP/1.1 200 OK
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>Untweetify Not Authorized</h1>
Authorization seems to have failed. :(
</body></html>
EOF
    sleep 1
    kill $NCPID
    rm response.pipe
    exit 2
  fi

  cat <<EOF >response.pipe
HTTP/1.1 200 OK
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>Untweetify Authorized</h1>
Yay. I am now authenticated and ready to nuke your tweets.
</body></html>
EOF
  sleep 1
  kill $NCPID
  rm response.pipe

  rm -f code.txt
  touch auth.json
  chmod 0600 auth.json
  curl --location --request POST 'https://api.twitter.com/2/oauth2/token' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "code=$CODE" \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "client_id=$TW_CLIENT_ID" \
    --data-urlencode 'redirect_uri=http://localhost:1666/' \
    --data-urlencode "code_verifier=$CHALLENGE" \
    -H "Authorization: Basic $BASIC_AUTH" >auth.json 2>/dev/null

  if ! grep refresh_token <auth.json 1>/dev/null 2>&1; then
    echo "Failed to authorize the app."
    rm -f auth.json
    exit 3
  fi

  echo "Yay. I am now authenticated and ready to nuke your tweets."
  exit 0
elif [ "$1" = "prep" ]; then
  if [ -z "$TW_ARCHIVE_PATH" ]; then
    echo "You need to set env var TW_ARCHIVE_PATH to point to where you unzipped your twitter data archive."
    exit 1
  fi
  rm -f pending.txt deleted.txt
  touch pending.txt
  for T in `ls $TW_ARCHIVE_PATH/data/tweets*.js|sort -r`; do
    echo "Processing tweets from $T"
    sed -re 's/^window\.YTD\.tweets.part[0-9]+ = //' <$T | jq '.[].tweet.id' | sed -re 's/"//g' >>pending.txt
  done
  touch deleted.txt
  exit 0
elif [ "$1" = "nuke" ]; then
  if ! [ -f auth.json ]; then
    echo "You need to authenticate first."
    exit 1
  fi
  if ! [ -f pending.txt ]; then
    echo "You need to prepare the data first."
    exit 2
  fi
  touch deleted.txt
  cat pending.txt | grep -v -f deleted.txt >toremove.txt
  DELETED=0
  FAILED=0
  COUNT=`wc -l toremove.txt`
  ACCESS_TOKEN=""
  N=0    
  # rate limit is 50/15min, do a bit less not to hit it
  BATCH=45
  SLEEP=960
  echo "Removing $COUNT tweets."
  split -l $BATCH -d toremove.txt toremove-
  for B in `ls toremove-*`; do
    echo "Processing batch $B, started @ `date`"
    REFRESH_TOKEN=`cat auth.json | jq .refresh_token | sed -re 's/"//g'`
    curl --request POST 'https://api.twitter.com/2/oauth2/token' \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "refresh_token=$REFRESH_TOKEN" \
      --data-urlencode 'grant_type=refresh_token' \
      --data-urlencode "client_id=$TW_CLIENT_ID" \
      -H "Authorization: Basic $BASIC_AUTH" >nuauth.json 2>/dev/null
    if ! grep refresh_token <nuauth.json 1>/dev/null 2>&1; then
      rm -f nuauth.json
      echo "Failed to authenicate."
      exit 3
    fi
    mv nuauth.json auth.json
    ACCESS_TOKEN=`cat auth.json | jq .access_token | sed -re 's/"//g'`
    for ID in `cat $B`; do
      RS=`curl -s -o /dev/null -w "%{http_code}" --location --request DELETE \
        "https://api.twitter.com/2/tweets/$ID" \
        -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null`
      echo "Deleted $ID: $RS"
      if [ "$RS" = "200" ]; then
        echo $ID >>deleted.txt
        DELETED=$(($DELETED+1))
      else
        echo $ID >>failed.txt
        FAILED=$(($FAILED+1))
      fi
      sleep 1
    done
    echo "Batch $B done, sleeping for $SLEEP seconds."
    sleep $SLEEP 
  done
  echo "Deleted $DELETED tweets, failed to delete $FAILED tweets."
  rm -f toremove.txt toremove-*
  exit 0
else
  echo "Usage: untweetify.sh [auth|prep|nuke]"
  exit 42
fi
