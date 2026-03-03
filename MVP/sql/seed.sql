INSERT INTO mvp_user (user_id, name) VALUES
  (10001, 'maker_lab'),
  (10002, 'taker_lab')
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO mvp_market (market, base_asset, quote_asset, amount_precision, price_precision) VALUES
  ('BTCUSDT', 'BTC', 'USDT', 6, 2),
  ('ETHUSDT', 'ETH', 'USDT', 6, 2)
ON DUPLICATE KEY UPDATE
  base_asset = VALUES(base_asset),
  quote_asset = VALUES(quote_asset),
  amount_precision = VALUES(amount_precision),
  price_precision = VALUES(price_precision);

INSERT INTO mvp_balance (user_id, asset, available, frozen) VALUES
  (10001, 'BTC', 20, 0),
  (10001, 'USDT', 500000, 0),
  (10002, 'BTC', 20, 0),
  (10002, 'USDT', 500000, 0)
ON DUPLICATE KEY UPDATE
  available = VALUES(available),
  frozen = VALUES(frozen);
