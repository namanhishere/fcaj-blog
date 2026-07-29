---
title: "Week 9 Worklog"
date: 2026-08-10
weight: 9
chapter: false
pre: " <b> 1.9. </b> "
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
---

### Week 9 Objectives:

* Write the internship report as a bilingual site that builds to a PDF, rather than as a document assembled by hand at the end.
* Finish the diagram set so every architectural claim in the report has a picture generated from a source file that is committed alongside it.
* Review what the deployment actually costs, and hand over a written list of what is done and what is not.

### Tasks to be carried out this week:

| Day | Task | Start Date | Completion Date | Reference Material |
| --- | ---- | ---------- | --------------- | ------------------ |
| 2   | - Set up the report as a bilingual Hugo site, every page as an English file plus a Vietnamese twin carrying the same weight and pre <br> - **Wire the PDF path rather than writing LaTeX by hand:** <br>&emsp; + scripts/convert_hugo_to_latex.py walks content/ and emits one .tex per page for each language <br>&emsp; + worklog pages set reportType worklog so the task table becomes a longtable <br>&emsp; + reportTableColumns narrows the five-column web table to three columns in the PDF <br> - Write the worklog for weeks 1 to 9, the proposal sections, and the workshop sessions in both languages | 10/08/2026 | 10/08/2026 | <https://gohugo.io/content-management/multilingual/> <br> <https://gohugo.io/content-management/front-matter/> |
| 3   | - Finish the PlantUML set: 22 sources in graph/src, each diagram with a Vietnamese twin, rendered to PNG and SVG and committed under static/images/diagrams as 44 files <br> - Use the PNG on every page that enters the PDF, because pdflatex cannot read SVG <br> - **Review the cost evidence rather than estimating:** <br>&emsp; + Cost Explorer answered, so the per-service table is labelled ACTUAL (Cost Explorer) <br>&emsp; + every measured line is below one cent per month, so it is not a monthly run-rate and is not presented as one <br>&emsp; + list price is quoted separately for anything run-rate shaped | 11/08/2026 | 11/08/2026 | <https://plantuml.com/> <br> <https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html> |
| 4   | - Record the largest structural cost decision with its arithmetic: natGateways is 0, so at ap-southeast-1 list price of 0.059 per gateway-hour the avoided fixed cost is 43.07 USD per month for one gateway, or 86.14 USD for the two that maxAzs 2 would provision by default <br> - **Write down the remaining work instead of leaving it implied:** <br>&emsp; + production has no CloudWatch alarms; the RaftDb namespace is provisioned but dormant <br>&emsp; + production is a single RaftDB voter, so there is no replication redundancy today <br>&emsp; + every deploy is a short full outage because one writer owns the EFS WAL <br> - Hand over the report site, the diagram sources and the evidence files | 12/08/2026 | 12/08/2026 | <https://aws.amazon.com/vpc/pricing/> <br> <https://calculator.aws/> |

The PDF is generated from the same markdown the site renders, so the front matter is what controls the report:

```yaml
reportType: worklog
reportTableColumns:
  - Day
  - Task
  - Completion Date
```

Diagram sources are compiled to both formats and the outputs are committed, because the published site and the PDF need different ones:

```bash
./graph/compile.sh
cp graph/output/*.png graph/output/*.svg static/images/diagrams/
```

### Week 9 Achievements:

* The report is a site rather than a document. Every page exists twice, once as `_index.md` and once as `_index.vi.md`, with the same `weight` and `pre` so the two sidebars match, and `python3 scripts/convert_hugo_to_latex.py` turns the whole tree into LaTeX for an English PDF and a Vietnamese one. The nine worklog weeks use the worklog renderer, which converts the five-column markdown task table into a `longtable` and keeps only the three columns named in `reportTableColumns`. Writing it this way meant every fact in the report is a page I can edit and rebuild, not a paragraph pasted into a template.

* The diagram set is complete and reproducible: 22 PlantUML sources in `graph/src/`, each diagram with a Vietnamese twin, rendered to both PNG and SVG and committed as 44 files under `static/images/diagrams/`. Pages that enter the PDF reference the PNG, because `pdflatex` cannot read SVG. The value of committing the renders alongside the sources is that a reader who does not have the Docker toolchain still sees the diagrams, and a reader who does can regenerate them and diff.

* The cost review is measured, and small enough that reporting it honestly matters more than reporting it impressively. Cost Explorer returned data, so the per-service table carries the label `ACTUAL (Cost Explorer)` for the June period and the partial July period that the API itself flags as estimated. Every single measured line is below one cent per month. That is a real number and it is also not a monthly run-rate for the architecture, so anything run-rate shaped in the report is quoted from AWS list price with the arithmetic shown and labelled as list price.

* The largest cost decision is structural rather than operational. The VPC is built with `natGateways: 0` and public subnets, and the Fargate task reaches the internet through its own public IP. At the `ap-southeast-1` list price of 0.059 USD per NAT-Gateway-hour that avoids 43.07 USD per month for a single gateway, or 86.14 USD per month for the two the CDK would provision by default for `maxAzs: 2`. Data-processing charges would be additional and are not quantified, because no gateway ever existed and there is therefore no byte count to multiply.

* The handover names the gaps rather than the features. Production runs one RaftDB voter, so there is no replication redundancy today and the documented three-voter target lives only in the staging factory. Production has no CloudWatch alarms, and the `RaftDb` custom namespace the dashboard is built on is provisioned but dormant until the runtime publishes values, so there is no metric history to hand over. Every deploy takes the canvas offline for the length of the deployment, deliberately, because one writer owns the EFS write-ahead log. Placement cooldowns are held in memory in the Go process and are lost on restart. The RaftDB protocol has no authentication layer, which is why the sidecar is reachable only over loopback.

* Two things about the report itself belong in the handover, because a reader will notice them. The internship ran nine weeks, from 15/06/2026 to 12/08/2026, and the programme's worklog template is written for twelve, so the mapping is stated in the timeline section instead of being padded out. And the report covers the worklog, the proposal, the blog posts and the workshop; the remaining template sections are not written, and the root page says so rather than linking to pages that do not exist.
