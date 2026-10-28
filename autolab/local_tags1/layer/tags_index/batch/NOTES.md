# tags_index batch-1 working notes
- config digest: 27ec8c53fe10634817f77f86b5b728d083d15ba98cd2171f293466eb2cc6d46d
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/tags_index/run_dse.rb
- launcher: /home/dev/project/reports/autolab/entrypoints/scaffold/tags_index/launch.sh
- targets: reports/autolab/targets/registry.json ; shims: reports/autolab/targets/shared_shims.rb
- scenarios: anon_json MAX_RUNS=24 TIME_BUDGET=300
- inputs: q (seed alice), limit (seed concolic)
- revisions measured: src_new ee9f17bc..., app 0760b6a2..., app_tree_digest 916d3937...1954 (all match addendum)
- extractor needs LANG=C.UTF-8 in my shell (US-ASCII scan error otherwise); 22 keys
