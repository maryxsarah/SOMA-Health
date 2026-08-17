-- Feedback spec item 4: daily_recommendation.message was shown at a fixed
-- 2-line limit and had no length contract on the server side, so a long
-- composed sentence (opening + data clause + why-clause + confidence
-- trailer) truncated mid-word on the card. reasoningMessage.ts now returns
-- { summary, detail }: `message` becomes the short, ~90-char-capped
-- summary (always fits); `message_detail` holds the fuller sentence,
-- surfaced through the existing "Why this?" disclosure instead of fighting
-- the card's line limit. Nullable -- rows written before this column
-- existed just have nothing more to show beyond `message` itself.
alter table daily_recommendation add column message_detail text;
