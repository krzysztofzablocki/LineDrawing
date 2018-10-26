![](https://github.com/krzysztofzablocki/smooth-drawing/raw/master/Example.png)
Line Drawing - Beautiful and fast smooth line drawing algorithm
--------------

When I was creating my app called [Foldify](http://foldifyapp.com), I needed a good quality drawing algorithm, there was a lack of proper end-to-end solution on the network.

Because of that gap in the knowdlege I've researched and implemented my own algorithm, using OpenGL to create anti-aliased lines at low cost, it also features speed based width similar to [Paper (by FiftyThree)](https://www.fiftythree.com/paper) app.

You can read tutorial explaining all the steps neccesary for creating this algorithm at my blog: http://www.merowing.info/2012/04/drawing-smooth-lines-with-cocos2d-ios-inspired-by-paper/

License
------------------
MIT. Use it for anything you want, just attribute my work. 
Let me know if you do use it somewhere, I'd love to hear about it :)

Enjoy && Share other crazy stuff. Let me know if you used

[Follow me on twitter](http://twitter.com/merowing_)

Building
------------------

This project now uses Cocos2d as a submodule. Cocos2d itself uses submodules now as well. Do not forget to git submodule update --init --recursive
