# CollectiveLabeler

A decentralized data annotation marketplace on Stacks blockchain where project creators request labeled data and labelers are paid per verified annotation through automated escrow.

## Features

- Create annotation tasks with automated escrow
- Submit labeled data with cryptographic verification
- Per-item payment upon verification
- Transparent tracking of task progress

## Smart Contract Functions

### Public Functions

- `create-task` - Create annotation task with description, reward, and item count
- `submit-annotation` - Submit labeled data with hash for verification
- `verify-and-pay` - Task creator verifies and releases payment
- `close-task` - Close task and return unused escrow funds

### Read-Only Functions

- `get-task` - Retrieve task details by ID
- `get-submission` - Get submission details including verification status
- `get-labeler-submission-count` - Count submissions from a labeler
- `get-next-task-id` - Get next available task ID

## Usage

Data projects can create annotation tasks with escrowed funds. Labelers submit their work with data hashes for verification. Upon approval, payment is automatically released. Unused funds are returned when tasks close.