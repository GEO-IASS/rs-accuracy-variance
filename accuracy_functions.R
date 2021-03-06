source_lines <- function(file, lines){
  source(textConnection(readLines(file)[lines]))
}



# metrics -----------------------------------------------------------------

get_conf_mat <- function(reps, true_id, pred_class, data) {
  table(as.character(pred_class[[reps]]),
        as.character(data[true_id[[reps]], "veg_class"]))
  # note danger here that it relies on always having at least one case for each class (that is, it relies on the alphabetical factor ordering to ensure confusion matrices are identical in structure)
}

dim_check <- function(x, len = 4) { # DANGER - hard coded to 4 classes, use len = if error matrix is different size
  dim(x)[1] != len | dim(x)[2] != len
}

percentage_agreement <- function(conf_mat) {
  # sum(as.character(data[true_id[[reps]], "veg_class"]) == as.character(pred_class[[reps]])) / length(pred_class[[reps]])
  if(dim_check(conf_mat)) {return(NA)}
  sum(diag(conf_mat)) / sum(conf_mat) # xtab method quicker?
}

cohens_kappa <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  # props <- conf_mat / sum(conf_mat)
  # cor_prob <- sum(diag(props))
  # chance_prob <- sum( apply(props, 1, sum) * apply(props, 2, sum) )
  # below seems to be a touch quicker...
  cor_prob <- sum(diag(conf_mat)) / sum(conf_mat)
  chance_prob <- crossprod(colSums(conf_mat) / sum(conf_mat), rowSums(conf_mat) / sum(conf_mat))[1]
  (cor_prob - chance_prob)/(1 - chance_prob)
}

# entropy and purity stolen from {IntNMF} package
entropy <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  inner_sum <- apply(conf_mat, 1, function(x) {
    c_size <- sum(x)
    sum(x * ifelse(x != 0, log2(x/c_size), 0))
  })
  -sum(inner_sum)/(sum(conf_mat) * log2(ncol(conf_mat)))
}

purity <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  sum(apply(conf_mat, 1, max)) / sum(conf_mat)
}

# disagreemetns kind of stolen from {diffeR} package
disagreement <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  1 - (sum(diag(conf_mat)) / sum(conf_mat))
}

quantity_disagreement <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  sum(abs(apply(conf_mat, 1, sum) - apply(conf_mat, 2, sum))) / 2 / sum(conf_mat)
}

allocation_disagreement <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(NA)}
  disagreement(conf_mat) - quantity_disagreement(conf_mat)
}

producer_accuracy <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(data.frame(NA,NA,NA,NA))} # DANGER - hard coded to 4 classes
  ret <- diag(conf_mat) / apply(conf_mat, 1, sum)
  names(ret) <- paste0(names(ret),"_prod")
  data.frame(as.list(ret))
}

user_accuracy <- function(conf_mat) {
  if(dim_check(conf_mat)) {return(data.frame(NA,NA,NA,NA))} # DANGER - hard coded to 4 classes
  ret <- diag(conf_mat) / apply(conf_mat, 2, sum)
  names(ret) <- paste0(names(ret),"_user")
  data.frame(as.list(ret))
}



# collect metrics ---------------------------------------------------------

collect_metric_results <- function(this_row, get_this, iter_n, data) {
  #sprint(get_this[this_row,])
  if (get_this$type[this_row] == "boot") {
    if (get_this$tt[this_row] %in% c("train", "test")) {
      true_id <- iter_n[["boot"]][[get_this$tt[this_row]]]
    } else {
      true_id <- rep(list(data$id), length(iter_n[["boot"]][[1]]))
    }
    conf_mat_list <- lapply(
      X = 1:length(iter_n[["boot"]][[1]]),
      FUN = get_conf_mat,
      true_id,
      iter_n[["boot"]][[get_this$method[this_row]]],
      data)
    users <- rbindlist(lapply(conf_mat_list, user_accuracy))
    producers <- rbindlist(lapply(conf_mat_list, producer_accuracy))
    return(
      data.frame(
        perc_agr = unlist(lapply(conf_mat_list, percentage_agreement)),
        kappa = unlist(lapply(conf_mat_list, cohens_kappa)),
        entropy = unlist(lapply(conf_mat_list, entropy)),
        purity = unlist(lapply(conf_mat_list, purity)),
        quant_dis = unlist(lapply(conf_mat_list, quantity_disagreement)),
        alloc_dis = unlist(lapply(conf_mat_list, allocation_disagreement)),
        users, producers,
        # method info
        type = get_this$type[this_row],
        method = get_this$method[this_row],
        scenario = get_this$scenario[this_row])
    )
  } else if (get_this$type[this_row] == "alldat") {
    the_conf_mat <- get_conf_mat(1, list(iter_n[["oob_ids"]]), list(iter_n[["alldat"]][[get_this$method[this_row]]]), data)
    return(data.frame(
      perc_agr = percentage_agreement(the_conf_mat),
      kappa = cohens_kappa(the_conf_mat),
      entropy = entropy(the_conf_mat),
      purity = purity(the_conf_mat),
      quant_dis = quantity_disagreement(the_conf_mat),
      alloc_dis = allocation_disagreement(the_conf_mat),
      user_accuracy(the_conf_mat), producer_accuracy(the_conf_mat),
      # method info
      type = get_this$type[this_row],
      method = get_this$method[this_row],
      scenario = get_this$scenario[this_row])
    )
  } else {
    if (get_this$tt[this_row] %in% c("train", "test")) {
      true_id <- iter_n[[get_this$scenario[this_row]]][[get_this$type[this_row]]][[get_this$tt[this_row]]]
    } else {
      true_id <- rep(list(data$id), length(iter_n[[get_this$scenario[this_row]]][[get_this$type[this_row]]][[1]]))
    }
    conf_mat_list <- lapply(
      X = 1:length(iter_n[[get_this$scenario[this_row]]][[get_this$type[this_row]]][[1]]),
      FUN = get_conf_mat,
      true_id,
      iter_n[[get_this$scenario[this_row]]][[get_this$type[this_row]]][[get_this$method[this_row]]],
      data)
    users <- rbindlist(lapply(conf_mat_list, user_accuracy))
    producers <- rbindlist(lapply(conf_mat_list, producer_accuracy))
    return(
      data.frame(
        perc_agr = unlist(lapply(conf_mat_list, percentage_agreement)),
        kappa = unlist(lapply(conf_mat_list, cohens_kappa)),
        entropy = unlist(lapply(conf_mat_list, entropy)),
        purity = unlist(lapply(conf_mat_list, purity)),
        quant_dis = unlist(lapply(conf_mat_list, quantity_disagreement)),
        alloc_dis = unlist(lapply(conf_mat_list, allocation_disagreement)),
        users, producers,
        # method info
        type = get_this$type[this_row],
        method = get_this$method[this_row],
        scenario = get_this$scenario[this_row])
    )
  }
}

collect_one_iteration <- function(iter_n, get_this, big_list, data) {
  print(paste0("Collecting iteration ", iter_n))
  print(Sys.time())
  rbindlist(lapply(
    X = 1:nrow(get_this),
    FUN = collect_metric_results,
    get_this,
    big_list[[iter_n]],
    data
  )) %>% mutate(iter_n = iter_n)
}

collect_image_results <- function(this_row, get_this, iter_n){
  if (get_this$type[this_row] == "boot") {
    area_tables <- iter_n[[get_this$scenario[this_row]]][[get_this$method[this_row]]]
  } else {
    area_tables <- iter_n[[get_this$scenario[this_row]]][[get_this$type[this_row]]][[get_this$method[this_row]]]
  }
  prop_tables <- lapply(area_tables, function(x) {x/sum(x)})
  data.frame(
    Banksia = unlist(lapply(prop_tables, `[[`, 1)),
    Eucalypt = unlist(lapply(prop_tables, `[[`, 2)),
    Teatree = unlist(lapply(prop_tables, `[[`, 3)),
    Wetheath = unlist(lapply(prop_tables, `[[`, 4)),
    # method info
    type = get_this$type[this_row],
    method = get_this$method[this_row],
    scenario = get_this$scenario[this_row])
}

collect_image_iteration <- function(iter_n, get_this, big_list) {
  print(paste0("Collecting iteration ", iter_n))
  print(Sys.time())
  rbindlist(lapply(
    X = 1:nrow(get_this),
    FUN = collect_image_results,
    get_this,
    big_list[[iter_n]]
  )) %>% mutate(iter_n = iter_n)
}



# transform data for plotting ---------------------------------------------

prettify_results <- function(metric_results) {
  # make a long df to plot various method/type combos
  
  print("Origins")
  metric_results$sample_origin <- NA
  metric_results$sample_origin[grep("test", metric_results$method)] <- "test"
  metric_results$sample_origin[grep("train", metric_results$method)] <- "train"
  metric_results$sample_origin[grep("true", metric_results$method)] <- "true"
  #metric_results$sample_origin[grep("all", metric_results$method)] <- "all"
  # metric_results$sample_origin <- factor(metric_results$sample_origin, 
  #                                        levels = c("true", "train", "test", "all"))
  metric_results$sample_origin <- factor(metric_results$sample_origin, 
                                         levels = c("true", "train", "test"))
  
  print("Designs")
  metric_results$sample_structure <- NA
  metric_results$sample_structure[grep("boot", metric_results$type)] <- "bootstrap"
  metric_results$sample_structure[grep("type1", metric_results$type)] <- "random"
  metric_results$sample_structure[grep("type2", metric_results$type)] <- "class"
  metric_results$sample_structure[grep("type3", metric_results$type)] <- "class-space"
  metric_results$sample_structure[grep("type4", metric_results$type)] <- "block"
  #metric_results$sample_structure[grep("alldat", metric_results$type)] <- "all-data"
  # metric_results$sample_structure <- factor(metric_results$sample_structure,
  #                                           levels = c("bootstrap", "random", "block", "class", "class-space", "all-data"))
  metric_results$sample_structure <- factor(metric_results$sample_structure,
                                            levels = c("bootstrap", "random", "block", "class", "class-space"))
  
  print("Fractions")
  metric_results$sample_fraction <- NA
  metric_results$sample_fraction[grep("boot", metric_results$type)] <- "bootstrap"
  metric_results$sample_fraction[grep("67", metric_results$type)] <- "67-33"
  metric_results$sample_fraction[grep("80", metric_results$type)] <- "80-20"
  metric_results$sample_fraction[grep("k5", metric_results$type)] <- "5-fold"
  #metric_results$sample_fraction[grep("alldat", metric_results$type)] <- "all-data"
  # metric_results$sample_fraction <- factor(metric_results$sample_fraction,
  #                                           levels = c("all-data", "bootstrap", "67-33", "80-20", "5-fold"))
  metric_results$sample_fraction <- factor(metric_results$sample_fraction,
                                           levels = c("bootstrap", "67-33", "80-20", "5-fold"))
  
  print("Models")
  metric_results$model <- NA
  metric_results$model[grep("lda", metric_results$method)] <- "max-likelihood"
  #metric_results$model[grep("knn", metric_results$method)] <- "nearest-n"
  metric_results$model[grep("rf", metric_results$method)] <- "random-forest"
  
  print("Go long!")
  metric_results_long <- metric_results %>%
    select(perc_agr:wh_prod, model, sample_structure, sample_fraction, sample_origin, iter_n) %>%
    gather("metric", "value", perc_agr:wh_prod) %>%
    mutate(metric = factor(metric, levels = c("perc_agr", "kappa", "entropy", "purity", "quant_dis", "alloc_dis",
                                              "bt_user", "ew_user", "ttt_user", "wh_user",
                                              "bt_prod", "ew_prod", "ttt_prod", "wh_prod"))) %>%
    filter(!is.na(value))
  
  print("Which tree?")
  metric_results_long$class <- NA
  metric_results_long$class[grep("bt", metric_results_long$metric)] <- "Banksia"
  metric_results_long$class[grep("ew", metric_results_long$metric)] <- "Eucalypt"
  metric_results_long$class[grep("ttt", metric_results_long$metric)] <- "Tea-tree"
  metric_results_long$class[grep("wh", metric_results_long$metric)] <- "Wet-heath"
  metric_results_long$class <- factor(metric_results_long$class,
                                      levels = c("Banksia","Eucalypt","Tea-tree","Wet-heath"))
  
  print("Which one?")
  metric_results_long$user_prod <- NA
  metric_results_long$user_prod[grep("user", metric_results_long$metric)] <- "user"
  metric_results_long$user_prod[grep("prod", metric_results_long$metric)] <- "producer"
  metric_results_long$user_prod <- factor(metric_results_long$user_prod,
                                          levels = c("user","producer"))
  
  metric_results_long
  
}

prettify_results_image <- function(metric_results) {
  # make a long df to plot various method/type combos
  
  print("Origins")
  metric_results$sample_origin <- factor("image")
  
  print("Designs")
  metric_results$sample_structure <- NA
  metric_results$sample_structure[grep("boot", metric_results$type)] <- "bootstrap"
  metric_results$sample_structure[grep("type1", metric_results$type)] <- "random"
  metric_results$sample_structure[grep("type2", metric_results$type)] <- "class"
  metric_results$sample_structure[grep("type3", metric_results$type)] <- "class-space"
  metric_results$sample_structure[grep("type4", metric_results$type)] <- "block"
  #metric_results$sample_structure[grep("alldat", metric_results$type)] <- "all-data"
  # metric_results$sample_structure <- factor(metric_results$sample_structure,
  #                                           levels = c("bootstrap", "random", "block", "class", "class-space", "all-data"))
  metric_results$sample_structure <- factor(metric_results$sample_structure,
                                            levels = c("bootstrap", "random", "block", "class", "class-space"))
  
  print("Fractions")
  metric_results$sample_fraction <- NA
  metric_results$sample_fraction[grep("boot", metric_results$type)] <- "bootstrap"
  metric_results$sample_fraction[grep("67", metric_results$type)] <- "67-33"
  metric_results$sample_fraction[grep("80", metric_results$type)] <- "80-20"
  metric_results$sample_fraction[grep("k5", metric_results$type)] <- "5-fold"
  #metric_results$sample_fraction[grep("alldat", metric_results$type)] <- "all-data"
  # metric_results$sample_fraction <- factor(metric_results$sample_fraction,
  #                                           levels = c("all-data", "bootstrap", "67-33", "80-20", "5-fold"))
  metric_results$sample_fraction <- factor(metric_results$sample_fraction,
                                           levels = c("bootstrap", "67-33", "80-20", "5-fold"))
  
  print("Models")
  metric_results$model <- NA
  metric_results$model[grep("lda", metric_results$method)] <- "max-likelihood"
  #metric_results$model[grep("knn", metric_results$method)] <- "nearest-n"
  metric_results$model[grep("rf", metric_results$method)] <- "random-forest"
  
  print("Go long!")
  metric_results_long <- metric_results %>%
    select(Banksia:Wetheath, model, sample_structure, sample_fraction, sample_origin, iter_n) %>%
    gather("metric", "value", Banksia:Wetheath) %>%
    mutate(metric = factor(metric, levels = c("Banksia","Eucalypt","Teatree","Wetheath"))) %>%
    filter(!is.na(value))
  
  print("Which tree?")
  metric_results_long$class <- NA
  metric_results_long$class[grep("Banksia", metric_results_long$metric)] <- "Banksia"
  metric_results_long$class[grep("Eucalypt", metric_results_long$metric)] <- "Eucalypt"
  metric_results_long$class[grep("Teatree", metric_results_long$metric)] <- "Tea-tree"
  metric_results_long$class[grep("Wetheath", metric_results_long$metric)] <- "Wet-heath"
  metric_results_long$class <- factor(metric_results_long$class,
                                      levels = c("Banksia","Eucalypt","Tea-tree","Wet-heath"))
  
  print("Which one?")
  metric_results_long$user_prod <- NA
  
  metric_results_long
}



# plots -------------------------------------------------------------------

pretty_breaks <- function(x) {
  seq(from = floor(x[1]), to = ceiling(x[2]), by = 2)
}

plot_pa_results <- function(x, data) {
  ggplot(data = data[data$iter_n %in% x,], aes(y = perc_agr)) +
    geom_boxplot(aes(x = type, colour = scenario, fill = method)) +
    scale_fill_manual(values = c("#fcbba1", "#fb6a4a", "#d4b9da", "#99d8c9", "#238b45")) +
    scale_colour_manual(values = c("#252525", "#e31a1c", "#3f007d"))
}

plot_by_structure <- function(data, model_type, 
                            origins = c("all", "train", "test"),
                            structures = c("bootstrap", "random","block", "class", "class-space", "all-data"),
                            metrics = c("perc_agr", "kappa", "entropy", "purity", "quant_dis", "alloc_dis"),
                            quants = c(0.05,0.5,0.9), suffix = "", scales = "free") {
  plt <- data %>%
    filter(sample_origin %in% origins,
           sample_structure %in% structures,
           model == model_type,
           metric %in% metrics) %>%
    ggplot(., aes(y = value)) +
    geom_violin(aes(x = sample_origin, fill = sample_fraction), scale = "area", draw_quantiles = quants, lwd=0.25) +
    scale_fill_manual("Resampling design", values = c("#969696", "#d55e00", "#f0e442", "#56b4e9")) +
    #scale_colour_manual("Sample type", values = c("#969696", "#fdae6b", "#d94801")) + 
    ylab("Accuracy metric value") + xlab("Stratification design") + ggtitle("Accuracy results by resampling and stratification design") +
    theme_bw() + theme(plot.title = element_text(hjust = 0.5)) +
    facet_grid(metric ~ sample_structure, scales = scales, space = "free", drop = T)
  ggsave(plot = plt, filename = paste0("plots/",model_type,suffix,".png"), device = "png", width = 20, height = 13)
}

plot_by_model <- function(data, model_type, 
                              origins = c("all", "train", "test"),
                              structures = c("bootstrap", "random","block", "class", "class-space", "all-data"),
                              metrics = c("perc_agr", "kappa", "entropy", "purity", "quant_dis", "alloc_dis"),
                              quants = c(0.05,0.5,0.9), suffix = "", scales = "free") {
  plt <- data %>%
    filter(sample_origin %in% origins,
           sample_structure %in% structures,
           model %in% model_type,
           metric %in% metrics) %>%
    ggplot(., aes(y = value)) +
    geom_violin(aes(x = model, fill = sample_fraction), scale = "area", draw_quantiles = quants, lwd=0.25) +
    scale_fill_manual("Resampling design", values = c("#969696", "#d55e00", "#f0e442", "#56b4e9")) +
    #scale_colour_manual("Sample type", values = c("#969696", "#fdae6b", "#d94801")) + 
    ylab("Accuracy metric value") + xlab("Model type") + ggtitle("Accuracy results by resampling and stratification design") + 
    facet_grid(metric ~ sample_structure, scales = scales, space = "free", drop = T) + 
    theme_bw() + theme(plot.title = element_text(hjust = 0.5))
  ggsave(plot = plt, filename = paste0("plots/",suffix,".png"), device = "png", width = 20, height = 13)
}

plot_user_prod <- function(data, model_type, 
                          origins = c("test"),
                          structures = c("bootstrap", "random","block", "class", "class-space"),
                          metrics = c("perc_agr", "bt_user", "ew_user", "ttt_user", "wh_user","perc_agr", "bt_prod", "ew_prod", "ttt_prod", "wh_prod"),
                          quants = c(0.05,0.5,0.9), suffix = "", scales = "free_x") {
  plt <- data %>%
    na.omit() %>%
    filter(sample_origin %in% origins,
           sample_structure %in% structures,
           model %in% model_type,
           metric %in% metrics) %>%
    ggplot(., aes(y = value)) +
    geom_violin(aes(x = user_prod, fill = sample_fraction), scale = "width", draw_quantiles = quants, lwd=0.25) +
    scale_fill_manual("Resampling design", values = c("#969696", "#d55e00", "#f0e442", "#56b4e9")) +
    #scale_colour_manual("Sample type", values = c("#969696", "#fdae6b", "#d94801")) + 
    ylab("Accuracy metric value") + xlab("Accuracy type") + ggtitle("Vegetation class accuracy results by resampling and stratification design") + 
    facet_grid(class ~ sample_structure, scales = scales, space = "free", drop = T) + 
    theme_bw() + theme(plot.title = element_text(hjust = 0.5))
  ggsave(plot = plt, filename = paste0("plots/",suffix,".png"), device = "png", width = 20, height = 13)
}
