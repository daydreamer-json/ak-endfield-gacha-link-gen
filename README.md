# Arknights Endfield gacha link generator

This repository stores scripts created to retrieve the gacha history URL for Arknights: Endfield.  
It is primarily intended for use with web services that manage gacha history.

## How to Use

Launch Windows PowerShell, paste the following code, and press Enter.
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex "&{$((New-Object System.Net.WebClient).DownloadString('https://github.com/daydreamer-json/ak-endfield-gacha-link-gen/raw/refs/heads/main/get_gacha_url.ps1'))}"
```

The gacha history URL will be automatically copied to your clipboard.

## Gacha history URL structure

The structure is as follows:
```plaintext
https://ef-webview.gryphline.com/api/record/char?server_id=2&pool_type=E_CharacterGachaPoolType_Standard&lang=en-us&token=xxxxxx
```

- `server_id` is the ID of the server containing the game data. For the global version, this is either `2` (Asia) or `3` (NA/EU).
- `pool_type` specifies the gacha type. It should be one of the following:
  - `E_CharacterGachaPoolType_Standard`
  - `E_CharacterGachaPoolType_Beginner`
  - `E_CharacterGachaPoolType_Special`
- `lang` is primarily used to localize character and item names. It is usually `en-us`.
- `token` specifies a unique U8 access token.

This API can only retrieve 5 records at a time. To fetch subsequent records, you must specify the seq_id. Specifying the seqId of the oldest record in the retrieved data (JS: `rsp.data.list.at(-1).seqId`) will retrieve the next page of data.

## Contributing

If you have any suggestions or proposals for improving the URL acquisition method, please feel free to submit a pull request or open an issue.

## To-do

- CN server methods

## Disclaimer

This project has no affiliation with Hypergryph and was created solely for private use, educational, and research purposes.

I assume no responsibility whatsoever. Please use it at your own risk.

---

(C) daydreamer-json
