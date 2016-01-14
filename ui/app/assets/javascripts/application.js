// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery-1.11.1.min
//= require jquery_ujs
//= require twitter/bootstrap
//= require_tree .

// Resize textareas automagically
$(function () {
  $("textarea").on('keyup', function () {
    $(this).height(0);
    $(this).height(this.scrollHeight);
  }).keyup();
});

function validateDdl(id) {
    var ddl = $('[id$=' + id + ']').val();
    $.ajax({
        method: "POST",
        url: "/parser",
        data: { msg: ddl },
        success: function(result) {
            var box = $('[id$=' + id +']').parent();
            if (ddl === "") {
                box.removeClass('has-success has-error');
            } else if (result.error === null) {
                box.removeClass('has-error');
                box.addClass('has-success');
            } else {
                box.removeClass('has-success');
                box.addClass('has-error');
            }
        },
        error: function(data) {
        },
        async: true
    });
}

function uniqueInDdl(id) {
    var ddl = $('[id$=' + id + ']').val();
    return /unique/i.test(ddl)
}

function columnsChangedInDdl(id) {
    var ddl = $('[id$=' + id + ']').val();
    return /(drop column)|(change column)|(modify column)|(alter column)|(drop table)/i.test(ddl)
}

function validateFinalInsert(id) {
    var finalInsert = $('[id$=' + id + ']').val();
    var box = $('[id$=' + id + ']').parent();
    if (/^(INSERT\s+INTO\s+)[^;]+$/i.test(finalInsert)) {
        if (finalInsert !== "") {
            box.removeClass('has-error');
            box.addClass('has-success');
        } else {
            box.removeClass('has-success');
        }
    } else {
        if (finalInsert !== "") {
            box.removeClass('has-success');
            box.addClass('has-error');
        } else {
            box.removeClass('has-error');
        }
    }
}

function alertOnDdl(ddl_id, form_class) {
    var alertMsgs = [];
    // alert about unique indexes in ddl statement
    if (uniqueInDdl(ddl_id)) {
        alertMsgs.push("We found the word 'unique' in your DDL statement. Please be extremely careful when adding unique " +
                      "constraints to a table as there is potential for data loss (existing duplicates for the unique key " +
                      "will get thrown away).\n\n\n Contact and admin if you have any questions.");
    }
    if (columnsChangedInDdl(ddl_id)) {
        alertMsgs.push("You are modifying/dropping at least 1 existing column. Be extra careful to make sure there won't " +
                       "be any unintended consequences from this.")
    }

    if (alertMsgs.length > 0) {
        var alertMsg = alertMsgs.join("<br/><br/>")

        // stop the submit action
        event.preventDefault();
        $.confirm({
            title: 'WARNING',
            content: alertMsg,
            confirmButton: 'Continue',
            confirmButtonClass: 'btn-default',
            cancelButton: 'Go Back',
            cancelButtonClass: 'btn-info',
            animationSpeed: 200,
            animation: 'scale',
            animationBounce: 2.5,
            confirm: function(){
              // do the submit action
              $("." + form_class).submit();
            },
            cancel: function(){
            }
        });
    };
}
