# Standard Notes Standalone Infrastructure

You can run your own Standard Notes server infrastructure and use it with any Standard Notes app. This allows you to have 100% control of your data. This setup is built with Docker and can be deployed in minutes.

**Requirements**

- Docker

**Data persistency**

Your MySQL Data will be written to your local disk in the `data` folder to keep it persistent between server runs.

### Getting started

1. Clone the project:

	```
	git clone --branch main https://github.com/standardnotes/standalone.git
	```

1. Setup the server by running:
```
./server.sh setup
```

1. Run the server by typing:
```
./server.sh start
```

Your server should now be available under http://localhost:3000

### Logs

You can check the logs of the running server by typing:

```
./server.sh logs
```

### Stopping the Server

In order to stop the server type:
```
./server.sh stop
```

### Updating to latest version

In order to update to the latest version of our software type:

```
./server.sh update
```

### Checking Status

You can check the status of running services by typing:
```
./server.sh status
```

### Cleanup Data

Please use this step with caution. In order to remove all your data and start with a fresh environment please type:
```
./server.sh cleanup
```
