# Benford audit check: first-two-digit test on corporate payments
# Run from the project root: Rscript analysis.R

library(benford.analysis)
library(dplyr)
library(ggplot2)

options(scipen = 999)
dir.create("output", showWarnings = FALSE)
data(corporate.payment)

# 1. First-two-digit Benford test (positive amounts >= 10) -----------------
bfd <- benford(corporate.payment$Amount, number.of.digits = 2, sign = "positive")
chi <- chisq(bfd)

summary_tbl <- data.frame(
  payments_tested = bfd$info$n,
  MAD             = round(bfd$MAD, 5),
  MAD_conformity  = bfd$MAD.conformity,   # Nigrini (2012) thresholds
  chi_square      = round(unname(chi$statistic), 0),
  df              = unname(chi$parameter),
  p_value         = if (chi$p.value < 1e-16) "< 1e-16" else signif(chi$p.value, 3)
)
print(summary_tbl)
write.csv(summary_tbl, "output/benford_summary.csv", row.names = FALSE)

# 2. Plot expected vs actual -------------------------------------------------
digits <- bfd$bfd %>%
  transmute(digits, actual = data.dist, expected = benford.dist,
            excess = data.dist.freq - benford.dist.freq)
top_digits <- digits %>% slice_max(excess, n = 5) %>% pull(digits)

p <- ggplot(digits, aes(digits)) +
  geom_col(aes(y = actual, fill = digits %in% top_digits), width = 0.8) +
  geom_line(aes(y = expected), colour = "black", linewidth = 0.7) +
  scale_fill_manual(values = c(`FALSE` = "grey65", `TRUE` = "#c0392b"),
                    labels = c("Actual", "Actual, top-5 excess"), name = NULL) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_continuous(breaks = seq(10, 90, 10)) +
  labs(title = "Corporate payments vs Benford's Law (first two digits)",
       subtitle = sprintf("n = %s payments | MAD = %.4f (%s) | line = Benford expected",
                         format(bfd$info$n, big.mark = ","), bfd$MAD, bfd$MAD.conformity),
       x = "First two digits", y = "Share of payments") +
  theme_minimal(base_size = 12) + theme(legend.position = "top")
ggsave("output/benford_first_two_digits.png", p, width = 10, height = 5.5, dpi = 150)

# 3. Top 20 suspicious payments ---------------------------------------------
# One row per vendor + amount; a payment scores one point for each red flag:
#   over-represented first-two digits (top-5 excess), duplicate (same vendor and
#   amount paid more than once), and round amount (multiple of 100).
suspects <- corporate.payment %>%
  filter(Amount >= 10) %>%
  mutate(first_two = floor(Amount / 10^(floor(log10(Amount)) - 1) + 1e-9)) %>%
  group_by(VendorNum, Amount, first_two) %>%
  summarise(n_payments = n(), total = sum(Amount),
            first_date = min(Date), last_date = max(Date), .groups = "drop") %>%
  mutate(flag_digits    = first_two %in% top_digits,
         flag_duplicate = n_payments > 1,
         flag_round     = Amount >= 100 & Amount %% 100 == 0,
         score = flag_digits + flag_duplicate + flag_round) %>%
  arrange(desc(score), desc(total)) %>%
  slice_head(n = 20)

print(suspects, width = Inf)
write.csv(suspects, "output/top20_suspicious_payments.csv", row.names = FALSE)
