namespace JieJu.Domain;

public sealed record ReviewOutcome(ReviewCard Card, ReviewLog Log);

public static class ReviewScheduler
{
    public const string Version = "jieju-interval-v1";

    public static ReviewOutcome Review(ReviewCard card, ReviewRating rating, DateTimeOffset at)
    {
        var established = card.State == ReviewState.Review && card.Repetitions > 0;
        var state = ReviewState.Review;
        double interval;
        var ease = card.EaseFactor;
        var repetitions = card.Repetitions;
        var lapses = card.Lapses;
        DateTimeOffset due;

        switch (rating)
        {
            case ReviewRating.Again:
                state = ReviewState.Learning;
                interval = 0;
                ease = Math.Max(1.3, ease - .2);
                repetitions = 0;
                if (established) lapses++;
                due = at.AddMinutes(10);
                break;
            case ReviewRating.Hard:
                interval = established ? RoundDays(Math.Max(1, card.IntervalDays * 1.2)) : 1;
                ease = Math.Max(1.3, ease - .15);
                repetitions++;
                due = at.AddDays(interval);
                break;
            case ReviewRating.Good:
                interval = established ? RoundDays(Math.Max(2, card.IntervalDays * ease)) : 2;
                repetitions++;
                due = at.AddDays(interval);
                break;
            case ReviewRating.Easy:
                interval = established ? RoundDays(Math.Max(4, card.IntervalDays * ease * 1.3)) : 4;
                ease = Math.Min(3, ease + .15);
                repetitions++;
                due = at.AddDays(interval);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(rating));
        }

        var updated = card with
        {
            State = state, DueAt = due, IntervalDays = interval, EaseFactor = ease,
            Repetitions = repetitions, Lapses = lapses, LastReviewedAt = at, UpdatedAt = at
        };
        var log = new ReviewLog(Guid.NewGuid(), card.Id, card.VocabularyEntryId, rating, at,
            card.State, card.IntervalDays, interval, due, Version);
        return new ReviewOutcome(updated, log);
    }

    private static double RoundDays(double value) => Math.Round(value, MidpointRounding.AwayFromZero);
}
