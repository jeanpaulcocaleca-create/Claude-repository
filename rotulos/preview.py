import sys
from PIL import Image
for name in sys.argv[1:]:
    im = Image.open(f'salida/{name}-70x110cm.png')
    im.convert('RGB').resize((1100, round(1100*im.size[1]/im.size[0])), Image.LANCZOS).save(f'salida/{name}-preview.jpg', quality=88)
    print(name, im.size)
