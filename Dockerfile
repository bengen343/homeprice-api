# Use the official lightweight Python image
FROM python:3.11-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install dependencies
# We do this before copying the rest of the code to cache the installation step
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy only the necessary Python script
COPY main.py .

# Command to run the script
CMD ["python", "main.py"]