from flask import Flask, render_template, request
import tensorflow as tf
import numpy as np
import os
import tensorflow_hub as hub
from tensorflow.keras.preprocessing import image
from tensorflow.keras.layers import Lambda
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'static/uploads'
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# Load the trained model
MODEL_PATH = "model/hybrid_dog_breed_classifier.keras"
model = tf.keras.models.load_model(
    MODEL_PATH,
    custom_objects={"vit_lambda": Lambda(lambda x: hub.KerasLayer("https://tfhub.dev/sayakpaul/vit_b16_fe/1")(x))}
)

# Define Class Labels (120 Breeds)
CLASS_NAMES = sorted(os.listdir("model/dataset/train"))

# Function to preprocess the image
def preprocess_image(img_path):
    img = image.load_img(img_path, target_size=(224, 224))
    img_array = image.img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0)
    img_array /= 255.0  # Normalize (0-1 range)
    return img_array

# Function to predict breed
def predict_breed(img_path):
    img_array = preprocess_image(img_path)
    predictions = model.predict(img_array)
    predicted_class_index = np.argmax(predictions[0])
    predicted_breed = CLASS_NAMES[predicted_class_index]
    confidence = np.max(predictions[0]) * 100
    return predicted_breed, confidence

@app.route('/', methods=['GET', 'POST'])
def home():
    if request.method == 'POST':
        if 'file' not in request.files:
            return render_template('index.html', error="No file uploaded")
        file = request.files['file']
        if file.filename == '':
            return render_template('index.html', error="No file selected")
        
        filename = secure_filename(file.filename)
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        file.save(filepath)
        
        breed, confidence = predict_breed(filepath)
        
        return render_template('index.html', filename=filename, breed=breed, confidence=confidence)
    return render_template('index.html')

if __name__ == '__main__':
    app.run(debug=True)