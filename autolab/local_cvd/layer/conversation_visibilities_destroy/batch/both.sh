#!/bin/bash
cd /home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d/batch
MAX_RUNS=90 TIME_BUDGET=900 bash drive.sh /home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d/batch logs/base.log
EXTRA_SEEDS_JSON=/home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d/batch/cooc_seeds.json SEEDS_ONLY=1 LABEL_SUFFIX=_cooc MAX_RUNS=90 TIME_BUDGET=900 bash drive.sh /home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d/batch logs/cooc.log
echo ALLDONE > logs/both.done
