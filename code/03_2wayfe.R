
cities1 <- readRDS("temp/cog_cities.rds") %>% 
  select(GEOID, lndper, total_revenue, share_state_fed, share_taxes, place_id) %>% 
  mutate(year = 2017)


cities2 <- inner_join(select(cities1, place_id, GEOID),
                      readRDS("temp/cog_12.rds")) %>% 
  select(GEOID, lndper, total_revenue, share_state_fed, share_taxes) %>% 
  mutate(year = 2012)

cities <- bind_rows(cities1, cities2) %>% 
  select(-place_id)

census <- bind_rows(
  readRDS("temp/census_14.rds") %>% 
    mutate(year = 2012),
  readRDS("temp/census_data.rds") %>% 
    mutate(year = 2017)
)

cities <- left_join(cities, census)

place_to <- readRDS("temp/place_to.rds") %>% 
  rename(plasub = place) %>% 
  mutate(votes_18 = count * to_18) %>% 
  select(plasub, votes_18, voters_18 = count,
         EthnicGroups_EthnicGroup1Desc)

p14 <- readRDS("temp/places_14_national.rds") %>% 
  select(plasub = place,
         EthnicGroups_EthnicGroup1Desc,
         votes_14 = ballots_14,
         voters_14)

place_to <- full_join(place_to, p14) %>% 
  mutate_at(vars(starts_with("vote")), ~ ifelse(is.na(.), 0, .))
################################
county_s_to <- readRDS("temp/county_s_to.rds") %>% 
  rename(plasub = county_s) %>% 
  mutate(votes_18 = count * to_18) %>% 
  select(plasub, votes_18, voters_18 = count,
         EthnicGroups_EthnicGroup1Desc)

cs14 <- readRDS("temp/countysubs_14_national.rds") %>% 
  select(plasub = cousub,
         EthnicGroups_EthnicGroup1Desc,
         votes_14 = ballots_14,
         voters_14)

county_s_to <- full_join(county_s_to, cs14) %>% 
  mutate_at(vars(starts_with("vote")), ~ ifelse(is.na(.), 0, .))

county_s_to <- county_s_to[!(county_s_to$plasub %in% place_to$plasub),]

city_to <- bind_rows(place_to, county_s_to)

city_to <- city_to[city_to$plasub %in% cities$GEOID, ]

to <- bind_rows(city_to %>% 
                  mutate(race = "overall"),
                city_to%>%
                  mutate(race = ifelse(EthnicGroups_EthnicGroup1Desc == "Likely African-American",
                                       "black",
                                       "nonblack")),
                city_to%>%
                  mutate(race = ifelse(EthnicGroups_EthnicGroup1Desc == "European",
                                       "white",
                                       "nonwhite")),
                city_to%>%
                  filter(!(EthnicGroups_EthnicGroup1Desc %in% c("European", "Likely African-American"))) %>% 
                  mutate(race = ifelse(EthnicGroups_EthnicGroup1Desc == "Hispanic and Portuguese", "latino",
                                       ifelse(EthnicGroups_EthnicGroup1Desc == "East and South Asian", "asian", "other")))) %>% 
  group_by(plasub, race) %>%
  summarize(voters_14 = sum(voters_14),
            voters_18 = sum(voters_18),
            votes_14 = sum(votes_14),
            votes_18 = sum(votes_18)) %>% 
  mutate(to_14 = votes_14 / voters_14,
         to_18 = votes_18 / voters_18) %>% 
  pivot_longer(cols = c("to_18", "to_14", "votes_18", "votes_14", "voters_18", "voters_14"), names_to = "year_var") %>% 
  cSplit("year_var", sep = "_", type.convert = F) %>% 
  rename(year = year_var_2, var = year_var_1) %>% 
  mutate(var = paste0(var, "_", race),
         year = ifelse(year == "18", 2017, 2012)) %>% 
  select(-race) %>% 
  pivot_wider(id_cols = c("plasub", "year"), names_from = "var")

cities1 <- inner_join(cities, to, by = c("GEOID" = "plasub", "year")) %>% 
  mutate(vap_to_overall =  votes_overall / cvap,
         vap_to_white =    votes_white / white_cvap,
         vap_to_black =    votes_black / black_cvap,
         vap_to_nonwhite = votes_nonwhite / nonwhite_cvap,
         vap_to_nonblack = votes_nonblack / (cvap - black_cvap),
         vap_to_latino =   votes_latino / latino_cvap,
         vap_to_asian =    votes_asian / asian_cvap,
         vap_to_other =    votes_other / other_cvap,
         state = substring(GEOID, 1, 2),
         median_income = median_income / 10000,
         pop_dens = log(pop_dens),
         total_revenue = log(total_revenue)) %>% 
  mutate_at(vars(starts_with("vap_to")), ~ ifelse(is.finite(.) & . > 1, 1, .))

#################################
cv <- c("lndper", "nh_white", "nh_black", "latino", "asian", "pop_dens", "total_revenue",
        "median_income", "some_college", "median_age", "share_over_64",
        "share_taxes", "share_state_fed", "year", "GEOID")


covars <- gsub("\\n|            ", "", "lndper + nh_white + nh_black + latino + asian + pop_dens +
            median_income + some_college + median_age + share_over_64 + total_revenue +
            share_taxes + share_state_fed")

ms <- data.frame(m = c("vap_to_overall", "vap_to_black", "vap_to_nonblack"),
                 name = c("Overall Turnout", "Black Turnout", "Non-Black Turnout"))

models <- lapply(ms$m, function(f){
  print(f)
  
  d <- cities1 %>% 
    select(!!sym(f), cv, voters_black)
  
  if(f == "vap_to_black"){
    d <- filter(d, voters_black > 0)
  }
  d <- select(d, -voters_black)
  
  d <- d[complete.cases(d),]
  d <- d[is.finite(rowSums(select(d, -GEOID))),] %>% 
    group_by(GEOID) %>% 
    filter(n() == 2)
  
  saveRDS(d, paste0("temp/", f, "_reg_data.rds"))
  
  plm(as.formula(paste0(f, " ~ ", covars)),
      data = d,
      index = c("GEOID", "year"), 
      model = "within", 
      effect = "twoways")
})

names(models) <- ms$name


modelsummary(models,
             statistic = "std.error",
             stars = c("*" = 0.05, "**" = 0.01, "***" = 0.001),
             coef_map = c("lndper" = "Log((Dollars / Resident) + 1)",
                          "nh_white" = "Share non-Hispanic White",
                          "nh_black" = "Share non-Hispanic Black",
                          "latino" = "Share Latinx",
                          "asian" = "Share Asian",
                          "pop_dens" = "Log(Population Density)",
                          "median_income" = "Median Income (\\$10,000s)",
                          "some_college" = "Share with Some College",
                          "median_age" = "Median Age",
                          "share_over_64" = "Share over 64 Years Old",
                          "total_revenue" = "Log(Total Revenue)",
                          "share_taxes" = "Share of Revenue from Taxes",
                          "share_state_fed" = "Share of Revenue from State / Federal Government",
                          "(Intercept)" = "Intercept"),
             gof_omit = 'DF|Deviance|AIC|BIC|Within|Pseudo|Log|Std|FE',
             title = "\\label{tab:twfe} Two-Way Fixed Effects Models",
             output = "latex",
             escape = FALSE) %>% 
  kable_styling(latex_options = c("scale_down", "HOLD_position")) %>%
  save_kable("temp/2wfe_reg_clean.tex")

modelsummary(models,
             statistic = "std.error",
             stars = c("*" = 0.05, "**" = 0.01, "***" = 0.001),
             coef_map = c("lndper" = "Log(Dollars / Resident)"),
             gof_omit = 'DF|Deviance|AIC|BIC|Within|Pseudo|Log|Std|FE',
             title = "\\label{tab:twfe} Two-Way Fixed Effects Models",
             latex_options = "scale_down",
             notes = rev(c("Covariates include: year and municipality fixed effects;
racial characteristics;", "population density; median income;
share with some college; median age", "and share of population over 64; total municipal revenue; share of municipal",
"revenue from taxes; share of municipal revenue from state and federal sources.")),
             output = "temp/2wfe_reg_clean_small.tex",
             escape = FALSE)



# marg <- ggeffect(m1, "lndper [0.01476405, 1.113368, 3.856901, 7.9801]")
# 
# ################################################
# bars <- data.frame(x = c(quantile(cities_bal$lndper, 0.1),
#                          quantile(cities_bal$lndper, 0.9)),
#                    y = c(marg$predicted[2:3])) %>% 
#   mutate(y = percent(y, accuracy = 0.1))
# 
# p2 <- ggplot() + 
#   geom_histogram(aes(x = lndper, y = ..count../3000), position="identity", linetype=1,
#                  fill="gray60", data = cities_bal, alpha=0.5, bins = 30) + 
#   geom_line(aes(x = x, y = predicted), data = marg, color = "black") +
#   geom_ribbon(aes(x = x, ymin = conf.low, ymax = conf.high), fill= "black", alpha=0.25, data = marg) +
#   xlab("Dollars per Resident") +
#   ylab("Turnout") + scale_x_continuous(breaks = c(log(1), log(2), log(11), log(101), log(201)),
#                                                labels = c("$0", "$1", "$10", "$100", "$200")) +
#   scale_y_continuous(labels = percent) +
#   coord_cartesian(xlim = c(-.3, log(201)), ylim = c(0, .825)) +
#   labs(caption = "Notes: Distribution of Dollars per Resident shown at bottom. Robust standard errors clustered by state.
# Covariates: % White, % Black, % Latinx, Median Income, % with Some College, Median Age, % Over 64 Years Old, 
# Population Density, Total Revenue, Share of Revenue from Taxes, Share of Revenue from State / Fed. Gov.
# Includes State, Year, and Municipality Fixed Effects.") +
#   theme_bw() + theme(plot.caption = element_text(hjust = 0),
#                      text = element_text(family = "LM Roman 10")) +
#   geom_vline(xintercept = bars$x[1], color = "black", linetype = "dashed") +
#   geom_vline(xintercept = bars$x[2], color = "black", linetype = "dashed") +
#   geom_text(aes(bars$x[1], .72, label = paste0(" Predicted Turnout at
#  10th Percentile:
#  ", bars$y[1]),
#                 family = "LM Roman 10", hjust = 0)) +
#   geom_text(aes(bars$x[2], .7, label = paste0(" Predicted Turnout at
#  90th Percentile:
#  ", bars$y[2]),
#                 family = "LM Roman 10", hjust = 0))
# 
# p2
# 
# saveRDS(p2, "temp/mef_2wfe.rds")

###########################################

cat <- full_join(cities1 %>% 
                   filter(year == 2017) %>% 
                   select(lndper_17 = lndper,
                          GEOID),
                 cities1 %>% 
                   filter(year == 2012) %>% 
                   select(lndper_12 = lndper,
                          GEOID)) %>% 
  mutate(treated = lndper_17 > lndper_12,
         change = lndper_17 / lndper_12) %>% 
  select(GEOID, treated, change)

cities1 <- left_join(cities1,
                     cat)

covars <- gsub("\\n|            ", "", "treated * I(as.factor(year)) + nh_white + nh_black +
            latino + asian + pop_dens +
            median_income + some_college + median_age + share_over_64 +
            share_taxes + share_state_fed")

models <- lapply(ms$m, function(f){
  print(f)
  
  d <- cities1 %>% 
    select(!!sym(f), cv, treated)
  
  d <- d[complete.cases(d),]
  d <- d[is.finite(rowSums(select(d, -GEOID))),] %>% 
    group_by(GEOID) %>% 
    filter(n() == 2)
  
  plm(as.formula(paste0(f, " ~ ", covars)),
      data = d,
      index = c("GEOID", "year"), 
      model = "within", 
      effect = "twoways")
})


stargazer(models, type = "text",
          covariate.labels = c("Treated $\\times$ 2018",
                               "Share non-Hispanic White",
                               "Share non-Hispanic Black",
                               "Share Latinx",
                               "Share Asian",
                               "Population Density",
                               "Median Income",
                               "Share with Some College",
                               "Median Age",
                               "Share over 64 Years Old",
                               # "Total Revenue",
                               "Share of Revenue from Taxes",
                               "Share of Revenue from State / Federal Government"),
          column.labels = ms$name,
          dep.var.labels = "",
          notes = "TO REPLACE",
          title = "\\label{tab:coarser} Two-Way Fixed Effects Models, Binary Treatment",
          out = "temp/coarser_reg.tex",
          order = 12,
          omit.stat = c("F", "ser"))

j <- fread("./temp/coarser_reg.tex", header = F, sep = "+")

note.latex <- "\\multicolumn{3}{l}{\\scriptsize{\\parbox{.5\\linewidth}{\\vspace{2pt}$^{***}p<0.01$, $^{**}p<0.05$, $^*p<0.1$.}}}"

j <- j %>%
  mutate(n = row_number(),
         V1 = ifelse(grepl("TO REPLACE", V1), note.latex, V1),
         V1 = ifelse(grepl("\\\\#tab", V1), gsub("\\\\#", "", V1), V1)) %>%
  filter(!grepl("Note:", V1))

insert1 <- "\\resizebox{1\\textwidth}{.5\\textheight}{%"
insert2 <- "}"

j <- bind_rows(j, data.frame(V1 = c(insert1, insert2), n = c(5.1, nrow(j) + 1 - 0.01))) %>%
  mutate(V1 = gsub("dollarsign", "\\\\$", V1)) %>%
  arrange(n) %>%
  select(-n)

write.table(j, "./temp/coarser_reg_clean.tex", quote = F, col.names = F,
            row.names = F)
