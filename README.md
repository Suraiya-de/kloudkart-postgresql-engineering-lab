
# Kloud Kart PostgreSQL Engineering Lab

A PostgreSQL engineering lab focused on data integrity, transaction safety, query optimisation, hierarchical data, and inventory auditing.

## Project Overview

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This project investigates and improves an existing PostgreSQL database while addressing practical database engineering challenges.

The lab focuses on four business requirements:

1. Prevent inventory overselling when multiple customers attempt to purchase the last available unit.
2. Improve customer spending reports, including monthly spending, order counts, running totals and customer rankings.
3. Support low-stock reporting across arbitrarily nested product categories.
4. Maintain an auditable record of inventory movements.

## Project Objectives

- Investigate existing data-quality and integrity problems.
- Design reliable PostgreSQL database structures and constraints.
- Implement safe transaction and concurrency handling.
- Improve reporting performance.
- Support recursive queries over category hierarchies.
- Maintain traceable inventory movements.
- Document technical decisions, assumptions and trade-offs.
- Test solutions against the supplied lab requirements.

## Repository Structure

```text
KloudKart-PostgreSQL-Engineering-Lab/
│
├── docs/
│   └── diagnosis/
│       └── data_diagnosis.md
│
├── sql/
├── tests/
├── scripts/
├── evidence/
│
├── README.md
└── .gitignore
```

## Current Progress

- [x] Docker and PostgreSQL environment setup.
- [x] Database creation and initial schema loading.
- [x] Loading and inspecting the supplied training data.
- [x] Initial data-integrity checks.
- [x] Investigation and documentation of initial data-quality findings.
- [ ] Working SQL solution.
- [ ] Technical decisions and trade-offs.
- [ ] Business memo.
- [ ] Additional improvement.

## Technology Stack

- PostgreSQL
- Docker
- Python
- SQL
- Git and GitHub

## Data Handling

The original training data contains customer-related information and is not included in this repository.

The original CSV files are kept locally. SQL scripts, documentation, tests and other non-sensitive project artefacts may be committed.

Reproducing the investigation requires authorised access to the supplied training resources.

## Current Documentation

- [Initial Data Diagnosis](docs/diagnosis/data_diagnosis.md)

## Project Status

The initial data investigation and diagnosis milestone is complete. The working SQL solution has not yet been started.
