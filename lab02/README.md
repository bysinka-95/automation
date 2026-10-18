# lab02 — currency_exchange_rate.py

The script gets the exchange rate of one currency against another currency on a date. It gets the
rate from the Currency Exchange Rate service ([lab02prep](https://github.com/mcroitor/automation/tree/main/labs/lab02prep)) and saves the rate in a JSON file.

## Installation

The script uses only the Python standard library. You do not need to install packages with `pip`.

1. Install Python 3.9 or later.
2. Start the service. The service needs Docker.

   ```bash
   cd lab02prep
   cp sample.env .env
   docker-compose up --build
   ```

   The service is available at `http://localhost:8080`.

3. Set the API key. Use the same key as in the `.env` file of the service.

   ```bash
   export API_KEY=EXAMPLE_API_KEY
   ```

## Usage

```sh
python3 currency_exchange_rate.py FROM TO DATE [--key KEY] [--url URL]
```

| Argument | Description                                                        |
| -------- | ------------------------------------------------------------------ |
| `FROM`   | Currency code to convert from: `MDL`, `USD`, `EUR`, `RON` or `UAH` |
| `TO`     | Currency code to convert to, from the same list                    |
| `DATE`   | Date in `YYYY-MM-DD` format, from `2025-01-01` to `2025-09-15`     |
| `--key`  | API key. The default is the `API_KEY` environment variable.        |
| `--url`  | Service URL. The default is `http://localhost:8080`.               |

The rate is the quantity of `FROM` currency for 1 unit of `TO` currency. For example, `USD EUR`
gives `1.045`. This means that 1 EUR = 1.045 USD.

Exit codes:

- `0` — the script saved the rate.
- `1` — an error occurred. The script writes the error to `error.log`.
- `2` — an argument is missing.

## Examples

Get the rate for 6 dates with an interval of 50 days:

```sh
$ python3 currency_exchange_rate.py USD EUR 2025-01-01
USD -> EUR on 2025-01-01: 1.0449967801462194
Saved to /path/to/automation/lab02/data/USD_EUR_2025-01-01.json

$ python3 currency_exchange_rate.py USD EUR 2025-02-20
USD -> EUR on 2025-02-20: 1.042397723382403
Saved to /path/to/automation/lab02/data/USD_EUR_2025-02-20.json

$ python3 currency_exchange_rate.py USD EUR 2025-04-11
USD -> EUR on 2025-04-11: 1.1073004958527646
Saved to /path/to/automation/lab02/data/USD_EUR_2025-04-11.json

$ python3 currency_exchange_rate.py USD EUR 2025-05-31
USD -> EUR on 2025-05-31: 1.1286984126984128
Saved to /path/to/automation/lab02/data/USD_EUR_2025-05-31.json

$ python3 currency_exchange_rate.py USD EUR 2025-07-20
USD -> EUR on 2025-07-20: 1.158498601017122
Saved to /path/to/automation/lab02/data/USD_EUR_2025-07-20.json

$ python3 currency_exchange_rate.py USD EUR 2025-09-08
USD -> EUR on 2025-09-08: 1.1693995616188957
Saved to /path/to/automation/lab02/data/USD_EUR_2025-09-08.json
```

Content of a saved file:

```sh
$ cat data/USD_EUR_2025-01-01.json
{
  "from": "USD",
  "to": "EUR",
  "rate": 1.0449967801462194,
  "date": "2025-01-01"
}
```

The script also accepts lower-case currency codes:

```sh
$ python3 currency_exchange_rate.py eur mdl 2025-05-31
EUR -> MDL on 2025-05-31: 0.051138600950155204
Saved to /path/to/automation/lab02/data/EUR_MDL_2025-05-31.json
```

Errors:

```sh
$ python3 currency_exchange_rate.py USD XYZ 2025-03-01
Error: USD -> XYZ on 2025-03-01: The currency XYZ is unknown

$ python3 currency_exchange_rate.py USD EUR 2025-02-30
Error: USD -> EUR on 2025-02-30: invalid date '2025-02-30', expected a real date in YYYY-MM-DD format

$ python3 currency_exchange_rate.py USD EUR 2030-01-01
Error: USD -> EUR on 2030-01-01: date 2030-01-01 is outside the available period 2025-01-01..2025-09-15

$ python3 currency_exchange_rate.py USD EUR 2025-03-01 --key WRONG
Error: USD -> EUR on 2025-03-01: Invalid API key

$ python3 currency_exchange_rate.py USD EUR 2025-03-01 --url http://localhost:9999
Error: USD -> EUR on 2025-03-01: request to http://localhost:9999 failed: [Errno 61] Connection refused

$ cat error.log
2026-09-27 23:50:25 ERROR USD -> XYZ on 2025-03-01: The currency XYZ is unknown
2026-09-27 23:50:25 ERROR USD -> EUR on 2025-02-30: invalid date '2025-02-30', expected a real date in YYYY-MM-DD format
...
```

## How the script works

1. `parse_args()` reads the command-line arguments.
2. `main()` checks that the API key is available.
3. `validate()` checks the parameters:
   - It changes the currency codes to upper case. Each code must have 3 letters.
   - The date must be a real date in `YYYY-MM-DD` format, from `2025-01-01` to `2025-09-15`.
4. `get_rate()` sends a POST request to the service, with the API key in the request body. It
   returns the `data` object of the response.
5. `save()` writes the `data` object to `data/FROM_TO_DATE.json`. It creates the `data` directory
   if the directory does not exist.
6. If a step fails, `log_error()` shows the error in the console and adds it to `error.log`. Then
   the script stops with exit code `1`.

The `data` directory and `error.log` are in the `lab02` directory, next to the script.

The script checks the parameters before the request because the service does not always report
errors:

- For a date in a different format, such as `2025-1-1`, the service returns a PHP error page
  instead of JSON.
- For a date without data, such as `2030-01-01`, the service returns the latest rate and no error.
- The service accepts only upper-case currency codes.

The service shows `RUS` in its currency list, but it has no `RUS` rates. All requests with `RUS`
fail with the error `Unknown currency rus`.
