from flask import Flask


app = Flask(__name__)
app.secret_key = "temp_key"

@app.route("/")
def home():
    return "Middle Man"


if __name__ == "__main__":
    app.run(debug=True, port=5001)