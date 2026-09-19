$ = (sel) -> document.querySelector sel

PREFIX = 'data:image/png;base64,'

inputItems = ['text', 'color', 'alpha', 'angle', 'space', 'size']
input = {}

image = $ '#image'
graph = $ '#graph'

state =
    file: null
    img: null
    canvas: null
    textCtx: null


dataURItoBlob = (dataURI) ->
    binStr = atob (dataURI.split ',')[1]
    len = binStr.length
    arr = new Uint8Array len

    for i in [0..len - 1]
        arr[i] = binStr.charCodeAt i
    new Blob [arr], type: 'image/png'


generateFileName = ->
    pad = (n) -> if n < 10 then '0' + n else n

    d = new Date
    '' + d.getFullYear() + '-' + (pad d.getMonth() + 1) + '-' + (pad d.getDate()) + ' ' + \
        (pad d.getHours()) + (pad d.getMinutes()) + (pad d.getSeconds()) + '.png'


formatBytes = (bytes) ->
    if bytes < 1024
        '' + bytes + ' B'
    else if bytes < 1024 * 1024
        (bytes / 1024).toFixed 1 + ' KB'
    else
        (bytes / 1024 / 1024).toFixed 1 + ' MB'


debounce = (fn, wait) ->
    timer = null
    return ->
        clearTimeout timer
        timer = setTimeout fn, wait


makeStyle = ->
    match = input.color.value.match /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i
    if not match?
        return 'rgba(0,0,255,' + input.alpha.value + ')'
    'rgba(' + (parseInt match[1], 16) + ',' + (parseInt match[2], 16) + ',' \
         + (parseInt match[3], 16) + ',' + input.alpha.value + ')'


redraw = ->
    return if not state.canvas?
    ctx = state.canvas.getContext '2d'
    ctx.clearRect 0, 0, state.canvas.width, state.canvas.height
    ctx.drawImage state.img, 0, 0


drawText = ->
    return if not state.canvas?
    text = input.text.value

    if state.textCtx?
        redraw()
    else
        state.textCtx = state.canvas.getContext '2d'

    return if text.length is 0

    textSize = input.size.value * Math.max 15, (Math.min state.canvas.width, state.canvas.height) / 25

    state.textCtx.save()
    state.textCtx.translate(state.canvas.width / 2, state.canvas.height / 2)
    state.textCtx.rotate (input.angle.value) * Math.PI / 180

    state.textCtx.fillStyle = makeStyle()
    state.textCtx.font = 'bold ' + textSize + 'px -apple-system,"Helvetica Neue",Helvetica,Arial,"PingFang SC","Hiragino Sans GB","WenQuanYi Micro Hei",sans-serif'

    width = (state.textCtx.measureText text).width
    step = Math.sqrt (Math.pow state.canvas.width, 2) + (Math.pow state.canvas.height, 2)
    margin = (state.textCtx.measureText '啊').width

    x = Math.ceil step / (width + margin)
    y = Math.ceil (step / (input.space.value * textSize)) / 2

    for i in [-x..x]
        for j in [-y..y]
            state.textCtx.fillText text, (width + margin) * i, input.space.value * textSize * j

    state.textCtx.restore()
    return


download = ->
    return if not state.canvas?
    link = document.createElement 'a'
    link.download = generateFileName()
    imageData = state.canvas.toDataURL 'image/png'
    blob = dataURItoBlob imageData
    link.href = URL.createObjectURL blob
    graph.appendChild link

    setTimeout ->
        link.click()
        graph.removeChild link
    , 100


updateValueLabels = ->
    setText = (id, text) ->
        el = $ '#' + id
        el.textContent = text if el?

    setText 'value-color', input.color.value
    setText 'value-alpha', input.alpha.value
    setText 'value-angle', input.angle.value + '°'
    setText 'value-space', input.space.value
    setText 'value-size', input.size.value


updateInfoBar = ->
    setText = (id, text) ->
        el = $ '#' + id
        el.textContent = text if el?

    if state.canvas?
        setText 'info-size', state.canvas.width + ' × ' + state.canvas.height + ' px'
    else
        setText 'info-size', '—'
    setText 'info-count', input.text.value.length + ' 字'


updateFileSize = ->
    el = $ '#info-weight'
    return if not el?
    if not state.canvas?
        el.textContent = '—'
        return
    dataURI = state.canvas.toDataURL 'image/png'
    bytes = Math.floor (dataURI.length - PREFIX.length) * 3 / 4
    el.textContent = formatBytes bytes


renderDebounced = debounce drawText, 120
updateFileSizeDebounced = debounce updateFileSize, 500


readFile = ->
    return if not state.file?

    fileReader = new FileReader

    fileReader.onload = ->
        img = new Image
        img.onload = ->
            state.img = img
            state.canvas = document.createElement 'canvas'
            state.canvas.width = img.width
            state.canvas.height = img.height
            state.canvas.title = '点击下载'
            state.textCtx = null

            ctx = state.canvas.getContext '2d'
            ctx.drawImage img, 0, 0

            drawText()
            updateInfoBar()
            updateFileSize()

            graph.innerHTML = ''
            graph.appendChild state.canvas

            state.canvas.addEventListener 'click', ->
                download()

        img.src = fileReader.result

    fileReader.readAsDataURL state.file


image.addEventListener 'change', ->
    state.file = @files[0]
    return if not state.file?
    return alert '仅支持 png, jpg, gif 图片格式' if state.file.type not in ['image/png', 'image/jpeg', 'image/gif']
    readFile()


inputItems.forEach (item) ->
    el = $ '#' + item
    input[item] = el

    el.addEventListener 'input', ->
        updateValueLabels()
        updateInfoBar()
        renderDebounced()
        updateFileSizeDebounced()
